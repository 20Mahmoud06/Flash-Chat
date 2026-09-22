import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/utils/message_preview.dart';
import 'package:flash_chat_app/core/utils/notification_ids.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/services/block/block_service.dart';
import 'package:flash_chat_app/features/chat/services/active_chat.dart';
import 'package:flash_chat_app/services/connectivity/connectivity_service.dart';
import 'package:flash_chat_app/services/fcm/fcm_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reliably delivers chat notifications even when the device was **offline**
/// or the app was **killed** (where a live FCM push may have been dropped or
/// never received).
///
/// When the app comes back online (or launches while already online) it
/// queries Firestore for messages that arrived while it was away and shows
/// notifications for the ones that:
///   * are not from the current user,
///   * are not from the currently-open chat / group,
///   * are from a conversation the user has not blocked.
///
/// A per-conversation "last handled message timestamp" is kept in
/// SharedPreferences. Each time a message is handled here (or shown by the
/// foreground FCM listener, or a chat is opened) that timestamp advances, so
/// already-seen messages are never re-notified and the backfill only ever
/// surfaces genuinely new, missed messages.
class MissedNotificationsService {
  MissedNotificationsService._();

  static final MissedNotificationsService instance =
      MissedNotificationsService._();

  static const String _prefsPrefix = missedNotificationsPrefsPrefix;
  static const Duration _startDelay = Duration(milliseconds: 3500);

  /// How long the backfill keeps redriving while FirebaseAuth is still
  /// restoring the session on a cold start (see [triggerBackfill]).
  static const Duration _authRetryDelay = Duration(seconds: 1);
  static const int _maxAuthRetries = 10;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  SharedPreferences? _prefs;
  final Map<String, int> _tsCache = {};
  bool _initialized = false;
  bool _running = false;
  bool _wasOnline = false;
  int _authRetries = 0;

  /// True once ANY signed-in user event fired for this process. The re-arm
  /// below must only run for the FIRST one (a cold start / app-update launch,
  /// where the session restores asynchronously) — a mid-process re-login must
  /// NOT re-notify: that would blast a burst of "your account" notifications
  /// + sounds right at every log in.
  bool _signedInOnce = false;

  /// Amount of chat/group messages to inspect per conversation on a backfill.
  static const int _perConversationLimit = 15;

  /// How old a "never-tracked" conversation's newest message may be and still be
  /// treated as genuinely missed (notify it). Anything older is treated as old
  /// pre-feature history and only used to establish the baseline silently.
  static const Duration _recentWindow = Duration(hours: 24);

  bool _isRecentlyMissed(DateTime timestamp) =>
      DateTime.now().difference(timestamp) <= _recentWindow;

  String _key(String peerId, {required bool isGroup}) => missedNotificationPrefKey(
        peerId,
        isGroup: isGroup,
      );

  /// Loads persisted state and wires the offline->online listener that
  /// triggers a backfill whenever connectivity is restored. Safe to call once
  /// from [main].
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _prefs = await SharedPreferences.getInstance();
    for (final key in _prefs!.getKeys()) {
      if (key.startsWith(_prefsPrefix)) {
        final ts = _prefs!.getInt(key);
        if (ts != null) {
          _tsCache[key.substring(_prefsPrefix.length + 1)] = ts;
        }
      }
    }

    _wasOnline = ConnectivityService.instance.isConnected.value;
    ConnectivityService.instance.isConnected
        .addListener(_onConnectivityChanged);

    // A cold start can outpace FirebaseAuth's async session restore. Re-arm
    // the backfill the moment a user is back so the FIRST launch after an app
    // update still backfills messages that arrived while the app was closed —
    // instead of only working from the second launch onward.
    _auth.authStateChanges().listen((user) {
      _authRetries = 0;
      if (user == null) return;
      if (_signedInOnce) return;
      _signedInOnce = true;
      if (ConnectivityService.instance.isConnected.value) {
        _scheduleBackfill();
      }
    });

    // Cold start while already online: backfill any messages that arrived
    // while the app was killed / offline.
    if (_wasOnline) {
      _scheduleBackfill();
    }
  }

  void _onConnectivityChanged() {
    final online = ConnectivityService.instance.isConnected.value;
    if (online && !_wasOnline) {
      _scheduleBackfill();
    }
    _wasOnline = online;
  }

  void _scheduleBackfill() {
    if (_backfillTimer != null) return;
    _backfillTimer = Timer(_startDelay, () {
      _backfillTimer = null;
      triggerBackfill();
    });
  }

  Timer? _backfillTimer;

  void dispose() {
    ConnectivityService.instance.isConnected
        .removeListener(_onConnectivityChanged);
    _backfillTimer?.cancel();
    _backfillTimer = null;
  }

  /// The latest handled message timestamp for a conversation (0 when unknown).
  int lastHandled(String peerId, {required bool isGroup}) =>
      _tsCache[_key(peerId, isGroup: isGroup)] ?? 0;

  /// Records the latest handled/notified message timestamp for a conversation
  /// so future backfills never re-notify it.
  Future<void> recordHandled(String peerId,
      {required bool isGroup, DateTime? timestamp}) async {
    final ts = (timestamp ?? DateTime.now()).millisecondsSinceEpoch;
    final key = _key(peerId, isGroup: isGroup);
    final current = _tsCache[key] ?? 0;
    if (ts <= current) return;
    _tsCache[key] = ts;
    try {
      await _prefs?.setInt(key, ts);
    } catch (e) {
      debugPrint('Failed to persist missed-notif timestamp: $e');
    }
  }

  /// Called when the user opens (or is already viewing) a conversation so the
  /// backfill stops notifying it. Also ensures any freshly-arrived push is
  /// being suppressed by the active-chat paths.
  Future<void> markChatOpened(String peerId, {required bool isGroup}) =>
      recordHandled(peerId, isGroup: isGroup);

  /// Queries Firestore for messages that arrived while the app was away and
  /// shows a notification for each conversation that has a genuinely new
  /// message not currently being viewed. Safe to call repeatedly.
  Future<void> triggerBackfill() async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) {
      // FirebaseAuth restores the persisted session asynchronously on a cold
      // start; racing it here would silently drop the whole backfill for this
      // launch (the "missed notifications only work after I reopen the app"
      // bug). Redrive briefly instead of bailing for good.
      if (_authRetries < _maxAuthRetries &&
          ConnectivityService.instance.isConnected.value) {
        _authRetries++;
        _backfillTimer?.cancel();
        _backfillTimer = Timer(_authRetryDelay, () {
          _backfillTimer = null;
          triggerBackfill();
        });
      }
      return;
    }
    if (!ConnectivityService.instance.isConnected.value) {
      return;
    }
    if (_running) return;
    _running = true;
    try {
      debugPrint('MissedNotifications: starting backfill');
      await _backfillOneOnOne(myUid);
      await _backfillGroups(myUid);
      debugPrint('MissedNotifications: backfill complete');
    } catch (e) {
      debugPrint('MissedNotifications: backfill error: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> _backfillOneOnOne(String myUid) async {
    final chats = await _firestore
        .collection('chats')
        .where('uids', arrayContains: myUid)
        .get();

    for (final chat in chats.docs) {
      final data = chat.data();
      final hiddenFor = (data['hiddenFor'] as List<dynamic>?) ?? const [];
      if (hiddenFor.contains(myUid)) continue;

      final uids = (data['uids'] as List<dynamic>?) ?? const [];
      if (uids.isEmpty) continue;
      // A self-chat has every element equal to my uid.
      final myUidStr = myUid;
      final isSelfChat = uids.toSet().length == 1 && uids.first == myUidStr;
      if (isSelfChat) continue;

      final peerId = uids
          .map((u) => u.toString())
          .firstWhere((u) => u != myUid, orElse: () => '');
      if (peerId.isEmpty) continue;

      final hadBaseline = lastHandled(peerId, isGroup: false) > 0;
      final missed = await _missedMessages(
        collectionPath: 'chats',
        chatId: chat.id,
        myUid: myUid,
        lastTs: lastHandled(peerId, isGroup: false),
        limit: _perConversationLimit,
      );

      if (missed.isEmpty) continue;

      // Never notify the conversation the user is currently reading.
      if (peerId == activeChatUserId) {
        await _advanceFromMessage(peerId, missed.first, isGroup: false);
        continue;
      }
      // Respect blocking.
      if (await _shouldSkip(missed.first.senderId)) {
        await _advanceFromMessage(peerId, missed.first, isGroup: false);
        continue;
      }

      // One notification per chat showing the newest message (the same
      // per-conversation id Android replaces automatically for older ones).
      final latest = missed.first;
      if (!await _shouldNotify(
        peerId: peerId,
        isGroup: false,
        latest: latest,
        hadBaseline: hadBaseline,
      )) {
        continue;
      }

      await _notifyLatest(
        isGroup: false,
        peerId: peerId,
        latest: latest,
        title: latest.senderName?.isNotEmpty == true
            ? latest.senderName!
            : 'New message',
      );
      // Mark the newest message handled so older ones are never re-notified.
      await _advanceFromMessage(peerId, latest, isGroup: false);
    }
  }

  Future<void> _backfillGroups(String myUid) async {
    final groups = await _firestore
        .collection('groups')
        .where('memberUids', arrayContains: myUid)
        .get();

    for (final group in groups.docs) {
      final data = group.data();
      final hiddenFor = (data['hiddenFor'] as List<dynamic>?) ?? const [];
      if (hiddenFor.contains(myUid)) continue;

      final memberUids =
          (data['memberUids'] as List<dynamic>?) ?? const <dynamic>[];
      if (!memberUids.map((u) => u.toString()).contains(myUid)) continue;

      final groupId = group.id;
      final rawName = data['name'] as String?;
      final groupName = (rawName != null && rawName.isNotEmpty)
          ? rawName
          : 'New Group Message';

      final hadBaseline = lastHandled(groupId, isGroup: true) > 0;
      final missed = await _missedMessages(
        collectionPath: 'groups',
        chatId: groupId,
        myUid: myUid,
        lastTs: lastHandled(groupId, isGroup: true),
        limit: _perConversationLimit,
      );

      if (missed.isEmpty) continue;

      // Never notify the group the user is currently reading.
      if (groupId == activeGroupId) {
        await _advanceFromMessage(groupId, missed.first, isGroup: true);
        continue;
      }
      // Respect blocking. A blocked 1-to-1 contact must NOT silence their
      // messages in the groups they're a member of, so the per-sender chat
      // block is deliberately not consulted here.
      final senderId = missed.first.senderId;
      if (senderId.isNotEmpty &&
          await BlockService.isEitherBlocked(senderId)) {
        await _advanceFromMessage(groupId, missed.first, isGroup: true);
        continue;
      }

      // One notification per group showing the newest message.
      final latest = missed.first;
      if (!await _shouldNotify(
        peerId: groupId,
        isGroup: true,
        latest: latest,
        hadBaseline: hadBaseline,
      )) {
        continue;
      }

      final senderName = latest.senderName?.isNotEmpty == true
          ? latest.senderName!
          : 'Someone';
      await _notifyLatest(
        isGroup: true,
        peerId: groupId,
        latest: latest,
        title: groupName,
        bodyPrefix: '$senderName: ',
      );
      // Mark the newest message handled so older ones are never re-notified.
      await _advanceFromMessage(groupId, latest, isGroup: true);
    }
  }

  /// Returns messages that are genuinely backfill-notifyable (sent by someone
  /// else, not deleted) and newer than the stored watermark.
  Future<List<MessageModel>> _missedMessages({
    required String collectionPath,
    required String chatId,
    required String myUid,
    required int lastTs,
    required int limit,
  }) async {
    Query query = _firestore
        .collection(collectionPath)
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit);

    if (lastTs > 0) {
      query = query.where('timestamp',
          isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastTs));
    }

    final snapshot = await query.get();
    final missed = <MessageModel>[];
    for (final doc in snapshot.docs) {
      final message = MessageModel.fromFirestore(doc);
      if (message.isDeleted) continue;
      if (message.senderId == myUid) continue;
      missed.add(message);
    }
    return missed;
  }

  /// Whether a 1-to-1 conversation should be skipped because either side
  /// blocked the other.
  Future<bool> _shouldSkip(String senderId) async {
    try {
      if (senderId.isNotEmpty && await BlockService.isEitherBlocked(senderId)) {
        return true;
      }
    } catch (e) {
      debugPrint('MissedNotifications: skip check failed: $e');
    }
    return false;
  }

  /// Advances the stored handled timestamp for a conversation to the message's
  /// timestamp without notifying (e.g. active chat or blocked).
  Future<void> _advanceFromMessage(String peerId, MessageModel message,
      {required bool isGroup}) {
    return recordHandled(peerId,
        isGroup: isGroup, timestamp: message.timestamp.toDate());
  }

  /// Decides whether a backfill hit should actually pop a notification, and
  /// when it should not, silently advances the watermark so the message is
  /// never re-surfaced later.
  ///
  /// Skips (advances watermark, no notification) when:
  ///   * [hadBaseline] is false and the newest message is not recent — the
  ///     conversation existed before the offline-backfill feature (or its
  ///     tracking was never started). Notifying every one of these at once is
  ///     exactly the "burst of old chat notifications on app open" bug, so
  ///     they only establish the baseline.
  ///   * The conversation already has a live notification in the shade (e.g.
  ///     the native FCM/HMS service rendered it while the app was closed).
  ///     Updating it again on cold start would re-sound and re-appear the
  ///     whole pile "at once".
  Future<bool> _shouldNotify({
    required String peerId,
    required bool isGroup,
    required MessageModel latest,
    required bool hadBaseline,
  }) async {
    if (!hadBaseline) {
      final recent = _isRecentlyMissed(latest.timestamp.toDate());
      await _advanceFromMessage(peerId, latest, isGroup: isGroup);
      if (!recent) return false;
    }

    final id = conversationNotificationId(peerId, isGroup: isGroup);
    if (await FcmService.hasActiveNotification(id)) {
      await _advanceFromMessage(peerId, latest, isGroup: isGroup);
      return false;
    }
    return true;
  }

  Future<void> _notifyLatest({
    required bool isGroup,
    required String peerId,
    required MessageModel latest,
    required String title,
    String bodyPrefix = '',
  }) async {
    final body =
        '$bodyPrefix${messagePreviewText(latest.toFirestore())}'.trim();

    final shouldShow = await FcmService.showNotificationFor(
      title: title,
      body: body,
      senderId: isGroup ? '' : latest.senderId,
      groupId: isGroup ? peerId : '',
      type: isGroup ? 'group_chat' : 'chat',
    );
    if (shouldShow) {
      debugPrint('MissedNotifications: notified [$peerId]: $body');
    }
  }
}
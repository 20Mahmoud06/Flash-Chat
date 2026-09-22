import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Details of a group call that is currently ringing / in progress.
class ActiveGroupCall {
  final String groupId;
  final String callId;
  final bool isVideo;
  final String groupName;
  final String callerId;
  final String callerName;

  const ActiveGroupCall({
    required this.groupId,
    required this.callId,
    required this.isVideo,
    required this.groupName,
    required this.callerId,
    required this.callerName,
  });

  factory ActiveGroupCall.fromDoc(String callId, Map<String, dynamic> data) {
    return ActiveGroupCall(
      groupId: data['groupId'] as String? ?? '',
      callId: callId,
      isVideo: data['isVideo'] == true,
      groupName: data['groupName'] as String? ?? '',
      callerId: data['callerId'] as String? ?? '',
      callerName: data['callerName'] as String? ?? '',
    );
  }
}

/// App-wide, read-only view of which group calls are currently active
/// (`ringing` or `accepted`). Lets any member who opens a group chat see that
/// a call is already running and tap to join it — no need to start a new ring.
///
/// Only ever tracks active calls (a small set), so a lightweight listener is
/// fine. Individual membership is resolved by the UI (the group chat already
/// knows its members), keeping this service decoupled from groups reads.
class GroupCallTracker extends ChangeNotifier {
  GroupCallTracker._();

  /// App-wide instance (one listener, shared by every screen).
  static final GroupCallTracker instance = GroupCallTracker._();

  final Map<String, ActiveGroupCall> _active = {};
  StreamSubscription? _sub;
  bool _started = false;

  /// A group call that is still `ringing` after this long is an orphan (the
  /// caller's app died / lost network before it ended). Showing its "ongoing
  /// call" card and ringing on every app open was a persistent bug.
  static const Duration _ringWindow = Duration(seconds: 45);

  /// Absolute ceiling for an `accepted` group call so an orphaned active doc
  /// can never show "ongoing" forever.
  static const Duration _maxCallAge = Duration(hours: 2);

  final Set<String> _endedCallIds = {};

  static const Duration _emptyParticipantsGrace = Duration(seconds: 20);

  /// Active group calls keyed by group id.
  Map<String, ActiveGroupCall> get activeCalls => Map.unmodifiable(_active);

  /// The active call for [groupId], or null if none.
  ActiveGroupCall? callForGroup(String groupId) => _active[groupId];

  /// Whether [callId] is one of the (non-stale) currently-active group calls.
  /// Used to hide "Join call" cards whose call already ended/was orphaned.
  bool isCallActive(String callId) =>
      _active.values.any((c) => c.callId == callId);

  bool get hasActiveCalls => _active.isNotEmpty;

  /// Begins listening (idempotent). Safe to call once at app startup.
  void start() {
    if (_started) return;
    _started = true;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _sub?.cancel();
        _sub = null;
        if (_active.isNotEmpty) {
          _active.clear();
          notifyListeners();
        }
        return;
      }
      _watch(user.uid);
    });
  }

  void _watch(String uid) {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('calls')
        .where('memberUids', arrayContains: uid)
        .where('status', whereIn: ['ringing', 'accepted'])
        .snapshots()
        .listen(_rebuild, onError: (Object e) {
      debugPrint('GroupCallTracker listen error: $e');
    });
  }

  void _rebuild(QuerySnapshot<Map<String, dynamic>> snap) {
    final updated = <String, ActiveGroupCall>{};
    final now = DateTime.now();
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['isGroup'] != true) continue;
      final groupId = data['groupId'] as String?;
      if (groupId == null || groupId.isEmpty) continue;

      final createdAt = data['createdAt'];
      final age = createdAt is Timestamp
          ? now.difference(createdAt.toDate())
          : Duration.zero;
      final status = data['status'] as String? ?? 'ringing';
      final participants = List<String>.from(
        data['participants'] as List? ?? const <String>[],
      );
      final callerId = data['callerId'] as String?;

      if (age > _maxCallAge) {
        _endOrphanedGroupCall(
            doc.id, status == 'ringing' ? 'no_answer' : 'ended');
        continue;
      }
      if (status == 'ringing' &&
          age > _ringWindow &&
          !participants.any((uid) => uid != callerId)) {
        _endOrphanedGroupCall(doc.id, 'no_answer');
        continue;
      }
      if (participants.isEmpty && age > _emptyParticipantsGrace) {
        _endOrphanedGroupCall(doc.id, 'ended');
        continue;
      }

      updated[groupId] = ActiveGroupCall.fromDoc(doc.id, data);
    }

    if (_mapsEqual(_active, updated)) return;
    _active
      ..clear()
      ..addAll(updated);
    notifyListeners();
  }

  void _endOrphanedGroupCall(String callId, String status) {
    if (_endedCallIds.contains(callId)) return;
    _endedCallIds.add(callId);
    FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .update({'status': status})
        .catchError((Object e) {
      debugPrint('GroupCallTracker auto-end $callId -> $status failed: $e');
    });
  }

  bool _mapsEqual(
    Map<String, ActiveGroupCall> a,
    Map<String, ActiveGroupCall> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (other.callId != entry.value.callId) return false;
      if (other.isVideo != entry.value.isVideo) return false;
    }
    return true;
  }
}

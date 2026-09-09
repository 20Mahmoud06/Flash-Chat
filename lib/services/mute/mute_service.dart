import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Per-contact notification muting, stored on my own user doc as
/// `mutedChats.<contactUid> = { until: Timestamp?, createdAt: Timestamp }`.
/// `until == null` means muted forever.
///
/// The mute state is read on the RECEIVER side (my own doc) before a
/// foreground notification is shown, and the SENDER of a message also checks
/// the recipient's `mutedChats` map before pushing — so a muted contact never
/// triggers a notification on ANY platform, including iOS in the terminated
/// state where the system renders the banner directly from the APNs alert.
class MuteService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static const Duration _cacheTtl = Duration(seconds: 60);
  static Map<String, dynamic>? _cache;
  static DateTime? _cacheLoadedAt;
  static Future<Map<String, dynamic>>? _pendingLoad;

  static String? get _myUid => _auth.currentUser?.uid;

  /// Whether a `mutedChats.<uid>` entry is currently active. `until == null`
  /// means the contact is muted forever; a `Timestamp`/`DateTime` means muted
  /// until that moment (an entry past its `until` counts as expired).
  static bool isMutedEntry(dynamic entry) {
    if (entry is! Map) return false;
    final until = entry['until'];
    if (until == null) return true;
    final date = until is Timestamp
        ? until.toDate()
        : (until is DateTime ? until : null);
    if (date == null) return true;
    return date.isAfter(DateTime.now());
  }

  /// True when I currently mute [peerUid]. Cached briefly to avoid a
  /// Firestore read on every incoming message.
  static Future<bool> isMuted(String peerUid) async {
    if (peerUid.isEmpty) return false;
    final chats = await _readMutedChats();
    return isMutedEntry(chats[peerUid]);
  }

  /// Mutes [peerUid]. `duration == null` mutes forever.
  static Future<void> setMute(String peerUid, {Duration? duration}) async {
    final uid = _myUid;
    if (uid == null || peerUid.isEmpty) return;
    await _firestore.collection('users').doc(uid).set({
      'mutedChats.$peerUid': {
        'until': duration == null
            ? null
            : Timestamp.fromDate(DateTime.now().add(duration)),
        'createdAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
    _invalidateCache();
  }

  /// Removes the mute for [peerUid].
  static Future<void> unmute(String peerUid) async {
    final uid = _myUid;
    if (uid == null || peerUid.isEmpty) return;
    try {
      await _firestore.collection('users').doc(uid).update({
        'mutedChats.$peerUid': FieldValue.delete(),
      });
    } catch (e) {
      // The `mutedChats` map (or the entry) does not exist yet — nothing to
      // remove, so failing here is the correct no-op outcome.
      debugPrint('MuteService.unmute no-op: $e');
    }
    _invalidateCache();
  }

  static Future<Map<String, dynamic>> _readMutedChats() async {
    final uid = _myUid;
    if (uid == null) return const {};
    final now = DateTime.now();
    if (_cache != null &&
        _cacheLoadedAt != null &&
        now.difference(_cacheLoadedAt!) < _cacheTtl) {
      return _cache!;
    }
    _pendingLoad ??= _load(uid);
    try {
      final value = await _pendingLoad!;
      if (_cache == null) {
        // A mute/unmute write landed while the load was in flight and cleared
        // the cache ("good" branch below would otherwise stamp this stale
        // result for up to [_cacheTtl]). Re-read directly (bypassing the
        // shared future so we never await ourselves) to return fresh state.
        final fresh = await _load(uid);
        _cache = fresh;
        _cacheLoadedAt = DateTime.now();
        return fresh;
      }
      // No write happened during the load; the shared value is still current.
      // Stamp it (fast path) and also use it as the deduped in-flight value.
      _cache = value;
      _cacheLoadedAt = DateTime.now();
      return value;
    } finally {
      _pendingLoad = null;
    }
  }

  static Future<Map<String, dynamic>> _load(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final map = doc.data()?['mutedChats'];
      return map is Map ? Map<String, dynamic>.from(map) : const {};
    } catch (e) {
      debugPrint('MuteService read failed: $e');
      return const {};
    }
  }

  static void _invalidateCache() {
    _cache = null;
    _cacheLoadedAt = null;
  }
}

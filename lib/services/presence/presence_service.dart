import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

/// Keeps the current user's online presence in sync with Firestore.
///
/// Each signed-in user owns one doc at `presence/{uid}` with
/// `{ online: bool, lastSeen: Timestamp }`:
///
/// * `online: true` is written when the app starts or returns to the
///   foreground; `online: false` + a fresh `lastSeen` when it goes to the
///   background.
/// * A heartbeat refresh keeps `lastSeen` current during long sessions. If
///   the app is killed abruptly, the heartbeat stops and readers treat the
///   stale `lastSeen` as "offline" (see [presenceStaleAfter]).
///
/// If the user disabled "show online status" in their profile
/// (`users/{uid}.presenceEnabled == false`), nothing is written and any
/// existing doc is deleted, so other users see no online info for them.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  /// Heartbeat interval used to keep `lastSeen` fresh while the app runs.
  static const Duration heartbeatInterval = Duration(seconds: 60);

  /// Readers treat an `online: true` doc with a `lastSeen` older than this
  /// as offline (the owner was likely killed without a clean lifecycle
  /// transition). Must be larger than [heartbeatInterval].
  static const Duration presenceStaleAfter = Duration(minutes: 2);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Timer? _heartbeat;
  String? _uid;
  bool _enabled = true;
  bool _started = false;

  DocumentReference get _presenceRef =>
      _firestore.collection('presence').doc(_uid!);

  /// Starts listening to auth changes. Safe to call multiple times.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _auth.authStateChanges().listen((user) async {
      if (user == null) {
        await _teardown();
        return;
      }
      _uid = user.uid;
      // Only track users who completed their profile and haven't disabled
      // the presence privacy setting.
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (!doc.exists) return;
        final data = doc.data();
        if ((data?['firstName'] as String? ?? '').isEmpty) return;
        _enabled = data?['presenceEnabled'] != false;
      } catch (_) {
        return;
      }
      if (_enabled) await _goOnline();
    });
  }

  /// Whether a user is currently offline / not reachable, based on their
  /// `presence/{uid}` doc. Returns `true` when the user disabled presence
  /// tracking, has no presence doc, is last seen too long ago, or explicitly
  /// went offline. Used to short-circuit a 1:1 call to the same quiet
  /// "unavailable" outcome as Messenger instead of ringing forever.
  Future<bool> isOffline(String uid) async {
    try {
      final doc = await _firestore.collection('presence').doc(uid).get();
      if (!doc.exists) return true;
      final data = doc.data() ?? {};
      final online = data['online'] == true;
      if (!online) return true;
      final lastSeen = data['lastSeen'];
      if (lastSeen is Timestamp) {
        final age = DateTime.now().difference(lastSeen.toDate());
        if (age > presenceStaleAfter) return true;
      }
      return false;
    } catch (e) {
      // Errors are treated as reachable (don't block a legitimate call).
      return false;
    }
  }

  /// Flips the privacy setting. When disabled, the presence doc is removed
  /// so nobody can see the user's online/last-seen status.
  Future<void> setPresenceEnabled(bool value) async {
    if (_uid == null || _enabled == value) return;
    _enabled = value;
    if (value) {
      await _goOnline();
    } else {
      _heartbeat?.cancel();
      _heartbeat = null;
      try {
        await _presenceRef.delete();
      } catch (_) {}
    }
  }

  Future<void> _goOnline() async {
    if (_uid == null || !_enabled) return;
    try {
      await _presenceRef.set({
        'online': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    _heartbeat ??= Timer.periodic(heartbeatInterval, (_) => _refreshLastSeen());
  }

  Future<void> _refreshLastSeen() async {
    if (_uid == null || !_enabled) return;
    try {
      await _presenceRef.update({
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _goOffline() async {
    if (_uid == null || !_enabled) return;
    try {
      await _presenceRef.set({
        'online': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _teardown() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final uid = _uid;
    _uid = null;
    if (uid != null) {
      try {
        await _firestore.collection('presence').doc(uid).delete();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _goOnline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _goOffline();
    }
  }
}

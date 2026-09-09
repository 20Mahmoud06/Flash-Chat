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

  /// Active group calls keyed by group id.
  Map<String, ActiveGroupCall> get activeCalls => Map.unmodifiable(_active);

  /// The active call for [groupId], or null if none.
  ActiveGroupCall? callForGroup(String groupId) => _active[groupId];

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
      _watch();
    });
  }

  void _watch() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('calls')
        .where('status', whereIn: ['ringing', 'accepted'])
        .snapshots()
        .listen(_rebuild, onError: (Object e) {
      debugPrint('GroupCallTracker listen error: $e');
    });
  }

  void _rebuild(QuerySnapshot<Map<String, dynamic>> snap) {
    final updated = <String, ActiveGroupCall>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['isGroup'] != true) continue;
      final groupId = data['groupId'] as String?;
      if (groupId == null || groupId.isEmpty) continue;
      updated[groupId] = ActiveGroupCall.fromDoc(doc.id, data);
    }

    if (_mapsEqual(_active, updated)) return;
    _active
      ..clear()
      ..addAll(updated);
    notifyListeners();
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

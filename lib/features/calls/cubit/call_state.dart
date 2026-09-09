import 'package:equatable/equatable.dart';

abstract class CallState extends Equatable {
  const CallState();

  @override
  List<Object?> get props => [];
}

class CallInitial extends CallState {}

class CallInitializing extends CallState {}

class CallPermissionDenied extends CallState {
  final String message;

  const CallPermissionDenied(this.message);

  @override
  List<Object?> get props => [message];
}

class CallEngineReady extends CallState {
  final List<int> remoteUids;
  final Set<int> mutedRemoteUids;
  final Set<int> mutedRemoteAudioUids;
  final Set<int> speakingUids;
  final bool isJoined;
  final bool isMuted;
  final bool isCameraOff;

  const CallEngineReady({
    this.remoteUids = const [],
    this.mutedRemoteUids = const {},
    this.mutedRemoteAudioUids = const {},
    this.speakingUids = const {},
    this.isJoined = false,
    this.isMuted = false,
    this.isCameraOff = false,
  });

  CallEngineReady copyWith({
    List<int>? remoteUids,
    Set<int>? mutedRemoteUids,
    Set<int>? mutedRemoteAudioUids,
    Set<int>? speakingUids,
    bool? isJoined,
    bool? isMuted,
    bool? isCameraOff,
  }) {
    return CallEngineReady(
      remoteUids: remoteUids ?? this.remoteUids,
      mutedRemoteUids: mutedRemoteUids ?? this.mutedRemoteUids,
      mutedRemoteAudioUids: mutedRemoteAudioUids ?? this.mutedRemoteAudioUids,
      speakingUids: speakingUids ?? this.speakingUids,
      isJoined: isJoined ?? this.isJoined,
      isMuted: isMuted ?? this.isMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
    );
  }

  @override
  List<Object?> get props => [
        remoteUids,
        mutedRemoteUids,
        mutedRemoteAudioUids,
        speakingUids,
        isJoined,
        isMuted,
        isCameraOff,
      ];
}

class CallEnded extends CallState {
  final String? reason;
  final Duration? duration;

  const CallEnded({this.reason, this.duration});

  @override
  List<Object?> get props => [reason, duration];
}

class CallError extends CallState {
  final String message;

  const CallError(this.message);

  @override
  List<Object?> get props => [message];
}

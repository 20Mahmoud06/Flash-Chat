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
  final bool isJoined;
  final bool isMuted;
  final bool isCameraOff;

  const CallEngineReady({
    this.remoteUids = const [],
    this.isJoined = false,
    this.isMuted = false,
    this.isCameraOff = false,
  });

  CallEngineReady copyWith({
    List<int>? remoteUids,
    bool? isJoined,
    bool? isMuted,
    bool? isCameraOff,
  }) {
    return CallEngineReady(
      remoteUids: remoteUids ?? this.remoteUids,
      isJoined: isJoined ?? this.isJoined,
      isMuted: isMuted ?? this.isMuted,
      isCameraOff: isCameraOff ?? this.isCameraOff,
    );
  }

  @override
  List<Object?> get props => [remoteUids, isJoined, isMuted, isCameraOff];
}

class CallEnded extends CallState {}

class CallError extends CallState {
  final String message;

  const CallError(this.message);

  @override
  List<Object?> get props => [message];
}
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../models/call_info.dart';

abstract class CallEvent {
  const CallEvent();
}

// ===============================
// USER-INITIATED EVENTS
// ===============================

class CallReset extends CallEvent {
  const CallReset();
}

class CallInitVideo extends CallEvent {
  final String channelName;
  final String callId;
  final CallInfo info;
  const CallInitVideo({
    required this.channelName,
    required this.callId,
    required this.info,
  });
}

class CallInitVoice extends CallEvent {
  final String channelName;
  final String callId;
  final CallInfo info;
  const CallInitVoice({
    required this.channelName,
    required this.callId,
    required this.info,
  });
}

class CallToggleMute extends CallEvent {
  const CallToggleMute();
}

class CallToggleCamera extends CallEvent {
  const CallToggleCamera();
}

class CallSwitchCamera extends CallEvent {
  const CallSwitchCamera();
}

class CallMinimize extends CallEvent {
  const CallMinimize();
}

class CallRestore extends CallEvent {
  const CallRestore();
}

class CallEnd extends CallEvent {
  final String callId;
  final String? reason;
  const CallEnd(this.callId, {this.reason});
}

// ===============================
// ENGINE-FIRED EVENTS
// ===============================

class CallJoinStateChanged extends CallEvent {
  final bool joined;
  const CallJoinStateChanged(this.joined);
}

class CallRemoteUserJoined extends CallEvent {
  final int uid;
  const CallRemoteUserJoined(this.uid);
}

class CallRemoteUserLeft extends CallEvent {
  final int uid;
  const CallRemoteUserLeft(this.uid);
}

class CallRemoteVideoMuted extends CallEvent {
  final int uid;
  final bool muted;
  const CallRemoteVideoMuted(this.uid, this.muted);
}

class CallRemoteAudioMuted extends CallEvent {
  final int uid;
  final bool muted;
  const CallRemoteAudioMuted(this.uid, this.muted);
}

class CallAudioVolumeChanged extends CallEvent {
  final List<AudioVolumeInfo> speakers;
  const CallAudioVolumeChanged(this.speakers);
}

class CallEngineError extends CallEvent {
  final String message;
  const CallEngineError(this.message);
}

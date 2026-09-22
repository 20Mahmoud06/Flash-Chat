import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/widgets.dart';

/// Agora video view for my own camera (uid 0).
Widget buildLocalVideoView(
  RtcEngine engine, {
  RenderModeType renderMode = RenderModeType.renderModeFit,
}) {
  return AgoraVideoView(
    controller: VideoViewController(
      rtcEngine: engine,
      canvas: VideoCanvas(
        uid: 0,
        renderMode: renderMode,
      ),
    ),
  );
}

/// Agora video view for a remote participant's camera.
Widget buildRemoteVideoView(
  RtcEngine engine,
  int uid,
  String channelName, {
  RenderModeType renderMode = RenderModeType.renderModeFit,
}) {
  return AgoraVideoView(
    controller: VideoViewController.remote(
      rtcEngine: engine,
      canvas: VideoCanvas(
        uid: uid,
        renderMode: renderMode,
      ),
      connection: RtcConnection(channelId: channelName),
    ),
  );
}

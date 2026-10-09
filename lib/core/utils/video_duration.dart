/// Chooses the duration to drive a video seek bar.
///
/// Video players load their length from the network controller. Right after a
/// send, the on-the-fly Cloudinary H.264 transform may still be deriving, so a
/// successful controller init can report an unknown (zero) duration — leaving
/// the seek bar dead and the label reading `00:00` until the asset is cached
/// and the chat is reopened. The chat persists the real length as
/// `MessageModel.videoDuration`; when the controller's duration is unknown,
/// that stored length keeps the seek bar and time labels correct immediately.
Duration effectiveVideoDuration(Duration controllerDuration, Duration? stored) {
  if (controllerDuration > Duration.zero) return controllerDuration;
  return stored ?? Duration.zero;
}
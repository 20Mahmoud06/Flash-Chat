import '../../models/message_model.dart';

/// Builds a human readable preview label for a reply to [message].
/// Used both when composing a reply and when rendering received replies.
///
/// [mediaCount] is the number of photos the reply targets: when it is greater
/// than 1 the reply is to the whole photo group ("📷 Photos") instead of a
/// single photo. Falls back to the message's own photo count when omitted.
String replyPreviewString(MessageModel message, {int? mediaCount}) {
  if (message.messageType == MessageType.image &&
      (mediaCount ?? (message.mediaUrls?.length ?? 1)) > 1) {
    return message.text.trim().isNotEmpty ? message.text : '📷 Photos';
  }
  return replyPreviewForType(message.messageType, message.text);
}

/// Builds a premium preview label from a message type + its caption / body.
/// Media messages keep the caption when present and otherwise fall back to a
/// clean "Photo" / "Video" / "Voice message" label instead of an empty line.
String replyPreviewForType(MessageType type, String text) {
  switch (type) {
    case MessageType.text:
      return text.trim().isEmpty ? 'Message' : text;
    case MessageType.image:
      return text.trim().isNotEmpty ? text : 'Photo';
    case MessageType.video:
      return text.trim().isNotEmpty ? text : 'Video';
    case MessageType.voice:
      return 'Voice message';
    case MessageType.system:
      return text.trim().isEmpty ? 'Message' : text;
    case MessageType.call:
      return text.trim().isEmpty ? 'Call' : text;
    case MessageType.callActive:
      return 'Live call';
  }
}

/// Parses the rich `repliedTo` metadata saved on outgoing messages back into
/// a [MessageType]. Old messages (pre rich-metadata) default to text.
MessageType replyPreviewType(Map<String, dynamic> meta) {
  final name = meta['type'] as String? ?? MessageType.text.name;
  for (final type in MessageType.values) {
    if (type.name == name) return type;
  }
  return MessageType.text;
}
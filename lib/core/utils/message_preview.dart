import 'package:flash_chat_app/models/message_model.dart';

/// Builds a human-friendly preview label for the chat list.
/// Media messages store their caption in [MessageModel.text], which is often
/// empty, so we fall back to a nice "📷 Photo" / "🎥 Video" / "🎤 Voice"
/// label that looks premium instead of an empty line.
String messagePreviewText(Map<String, dynamic>? msg) {
  if (msg == null || msg.isEmpty) return 'No messages yet 👀';

  if (msg['isDeleted'] == true) {
    return '🚫 This message was deleted';
  }

  final type = msg['messageType'] as String? ?? MessageType.text.name;
  switch (type) {
    case 'image':
      final urls = msg['mediaUrls'];
      final count = urls is List ? urls.length : 1;
      return count > 1 ? '📷 Photos' : '📷 Photo';
    case 'video':
      return '🎥 Video';
    case 'voice':
      final dur = msg['voiceDuration'];
      if (dur is int && dur > 0) {
        final m = (dur ~/ 60).toString().padLeft(2, '0');
        final s = (dur % 60).toString().padLeft(2, '0');
        return '🎤 Voice message · $m:$s';
      }
      return '🎤 Voice message';
    case 'call':
      final isVideo = msg['callType'] == 'video';
      final outcome = msg['callOutcome'] as String?;
      final label = isVideo ? 'Video call' : 'Voice call';
      final outcomeLabel = _callOutcomeLabel(outcome);
      // A completed call with a known duration reads nicely like
      // "📞 Voice call · 5:32"; otherwise show the outcome
      // ("· Missed", "· Declined", …).
      if (outcome == 'completed') {
        final durSec = (msg['callDuration'] as num?)?.toInt() ?? 0;
        if (durSec > 0) {
          final m = (durSec ~/ 60).toString().padLeft(2, '0');
          final s = (durSec % 60).toString().padLeft(2, '0');
          return '${isVideo ? '📹' : '📞'} $label · $m:$s';
        }
      }
      return '${isVideo ? '📹' : '📞'} $label · $outcomeLabel';
    default:
      return (msg['text'] as String?) ?? '';
  }
}

String formatVoiceDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _callOutcomeLabel(String? outcome) {
  switch (outcome) {
    case 'missed':
      return 'Missed';
    case 'declined':
      return 'Declined';
    case 'cancelled':
      return 'Cancelled';
    case 'busy':
      return 'Busy';
    default:
      return 'Call ended';
  }
}

/// FNV-1a 64-bit hashing for deterministic notification ids.
///
/// The native HMS notification code in
/// android/app/src/main/kotlin/com/example/flash_chat_app/hms/HmsMessageService.kt
/// implements the exact same algorithm, so Dart can cancel notifications that
/// the native service showed (and vice versa) without sharing state.
library;

int fnv1a64(String input) {
  // 0xcbf29ce484222325 as a signed 64-bit int (same bit pattern).
  var hash = -3750763034362895579;
  const prime = 1099511628211; // 0x100000001b3
  for (final unit in input.codeUnits) {
    hash = (hash ^ unit) * prime;
  }
  return hash;
}

/// Stable notification id for a conversation. `peerId` is the contact uid for
/// 1-to-1 chats and the group id for group chats.
int conversationNotificationId(String peerId, {required bool isGroup}) {
  final base = fnv1a64(peerId) & 0xFFFFF;
  return isGroup ? 2000000 + base : base;
}

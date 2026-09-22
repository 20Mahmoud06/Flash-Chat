import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';

/// Scrolls a message that is already built on screen to the center of the
/// viewport. Handles the reversed list manually instead of using
/// Scrollable.ensureVisible (which is unreliable with reverse: true).
/// Retries until the message is built or it runs out of attempts.
void scrollMessageToViewport({
  required ScrollController controller,
  required Map<String, GlobalKey> messageKeys,
  required ChatCubit cubit,
  required bool Function() isMounted,
  required String messageId,
}) {
  void centerMessage(BuildContext targetCtx) {
    if (!controller.hasClients) return;
    final box = targetCtx.findRenderObject() as RenderBox?;
    final viewport = box == null ? null : RenderAbstractViewport.of(box);
    if (box == null || viewport == null) return;
    final viewportTop = (viewport as RenderBox).localToGlobal(Offset.zero).dy;
    final distanceFromTop = box.localToGlobal(Offset.zero).dy - viewportTop;
    final position = controller.position;
    // Reversed list: content grows upward, so a larger offset = higher up.
    final target =
        (position.pixels + position.viewportDimension / 2 - distanceFromTop)
            .clamp(0.0, position.maxScrollExtent)
            .toDouble();
    position.animateTo(target,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  void tryScroll([int attempt = 0]) {
    if (!isMounted()) return;
    final key = messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx != null && ctx.mounted) {
      centerMessage(ctx);
      return;
    }

    if (cubit.state is! ChatLoaded || !controller.hasClients) {
      if (attempt < 14) {
        Future.delayed(const Duration(milliseconds: 80), () {
          if (isMounted()) tryScroll(attempt + 1);
        });
      }
      return;
    }

    final messages = (cubit.state as ChatLoaded).messages;
    final idToIndex = {
      for (int i = 0; i < messages.length; i++) messages[i].id: i,
    };
    final index = idToIndex[messageId];
    if (index == null) {
      // The message may still be loading (pagination in flight).
      if (attempt < 14) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (isMounted()) tryScroll(attempt + 1);
        });
      }
      return;
    }

    final position = controller.position;
    final viewportH = position.viewportDimension;
    if (viewportH <= 0) {
      if (attempt < 14) {
        Future.delayed(const Duration(milliseconds: 80), () {
          if (isMounted()) tryScroll(attempt + 1);
        });
      }
      return;
    }

    // Estimate the target's position by anchoring on the closest message
    // that is already built (measured exactly). Guessing `index * 85`
    // fails badly when photos / videos / reply cards make bubbles taller.
    int? anchorIndex;
    double? anchorContentTop;
    double builtHeightSum = 0;
    int builtCount = 0;
    for (final entry in messageKeys.entries) {
      final anchorCtx = entry.value.currentContext;
      if (anchorCtx == null || !anchorCtx.mounted) continue;
      final anchorMsgIndex = idToIndex[entry.key];
      if (anchorMsgIndex == null || anchorMsgIndex == index) continue;
      final anchorBox = anchorCtx.findRenderObject() as RenderBox;
      final viewportBox = RenderAbstractViewport.of(anchorBox) as RenderBox;
      final distanceFromTop = anchorBox.localToGlobal(Offset.zero).dy -
          viewportBox.localToGlobal(Offset.zero).dy;
      final contentTop = position.pixels + viewportH - distanceFromTop;

      final bool isCloser;
      if (anchorIndex == null) {
        isCloser = true;
      } else if (anchorMsgIndex < index) {
        isCloser = anchorMsgIndex > anchorIndex;
      } else {
        isCloser = anchorMsgIndex < anchorIndex;
      }
      if (isCloser) {
        anchorIndex = anchorMsgIndex;
        anchorContentTop = contentTop;
      }
      if (anchorMsgIndex < index) {
        builtHeightSum += anchorBox.size.height;
        builtCount++;
      }
    }

    // Estimated height of one message inside the unbuilt gap.
    final localAvg = builtCount > 0
        ? builtHeightSum / builtCount
        : (position.maxScrollExtent + viewportH) / messages.length;

    double targetContentTop;
    if (anchorIndex != null && anchorContentTop != null) {
      // The target is `gap` messages away from the measured anchor. Each
      // retry re-measures from the now-better built anchors, so the
      // estimate converges instead of overshooting.
      final gap = index - anchorIndex;
      targetContentTop = anchorContentTop + gap * localAvg;
    } else {
      // No built anchor yet: fall back to the whole-list average.
      targetContentTop = (index + 1) * localAvg;
    }

    final target = (targetContentTop - viewportH / 2)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();

    // Already where the estimate says: stop scrolling; the retries below
    // keep checking for the built bubble so the final center is exact.
    if ((target - position.pixels).abs() >= 4) {
      position.animateTo(target,
          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
    }

    if (attempt < 14) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (isMounted()) tryScroll(attempt + 1);
      });
    }
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll(0));
}

/// True when [messageId]'s bubble is built and fully inside the viewport.
/// Used to skip scrolling when the target is already on screen.
bool isMessageFullyVisible({
  required ScrollController controller,
  required Map<String, GlobalKey> messageKeys,
  required String messageId,
}) {
  if (!controller.hasClients) return false;
  final ctx = messageKeys[messageId]?.currentContext;
  if (ctx == null || !ctx.mounted) return false;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null) return false;
  final viewportBox = RenderAbstractViewport.of(box) as RenderBox;
  final top = box.localToGlobal(Offset.zero).dy;
  final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
  final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
  final viewportBottom = viewportTop + viewportBox.size.height;
  return top >= viewportTop && bottom <= viewportBottom;
}

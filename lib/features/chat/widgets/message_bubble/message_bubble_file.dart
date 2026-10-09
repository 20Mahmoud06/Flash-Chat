import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/services/media/file_message_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/message_model.dart';

/// WhatsApp-style file bubble: a type icon (PDF / Word / Excel), the file
/// name, size and extension — plus an "Open" pill and a download button.
/// Opening streams the file into the right external app; downloading saves it
/// into the device's public Downloads folder.
class MessageFileCard extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final Color textColor;
  final Color bubbleColor;
  final VoidCallback? onShowOptions;

  const MessageFileCard({
    super.key,
    required this.message,
    required this.isMe,
    required this.textColor,
    required this.bubbleColor,
    this.onShowOptions,
  });

  @override
  State<MessageFileCard> createState() => _MessageFileCardState();
}

class _MessageFileCardState extends State<MessageFileCard> {
  bool _busy = false;
  bool _downloaded = false;

  String get _fileName => widget.message.fileName ?? 'File';

  String? get _url => (widget.message.mediaUrls?.isNotEmpty ?? false)
      ? widget.message.mediaUrls!.first
      : null;

  @override
  void initState() {
    super.initState();
    _checkDownloaded();
  }

  /// A locally cached copy means the file has already been downloaded, so the
  /// card can swap its single action from "download" to "Open".
  Future<void> _checkDownloaded() async {
    final cached = await FileMessageService.cachedFile(_fileName);
    if (!mounted) return;
    setState(() => _downloaded = cached != null);
  }

  /// Tapping the card downloads the file first and opens it — only after a
  /// local copy exists — so the two share the same single-tap gesture.
  Future<void> _handleTap() async {
    if (_busy || _url == null) return;
    if (_downloaded) {
      await _handleOpen();
    } else {
      await _handleDownload();
    }
  }

  Future<void> _handleOpen() async {
    final url = widget.message.mediaUrls?.isNotEmpty ?? false
        ? widget.message.mediaUrls!.first
        : null;
    if (url == null || _busy) return;

    setState(() => _busy = true);
    try {
      final file = await FileMessageService.downloadToCache(url, _fileName);
      if (!mounted) return;
      setState(() => _busy = false);
      await FileMessageService.open(file.path);
    } catch (e) {
      debugPrint('File open failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: CustomText(text: 'Could not open this file.')),
      );
    }
  }

  /// Downloads the file into the app cache so it becomes openable. Saving to
  /// the device's Downloads folder is a separate, explicit action ([_handleSave]).
  Future<void> _handleDownload() async {
    final url = widget.message.mediaUrls?.isNotEmpty ?? false
        ? widget.message.mediaUrls!.first
        : null;
    if (url == null || _busy) return;

    setState(() => _busy = true);
    try {
      await FileMessageService.downloadToCache(url, _fileName);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _downloaded = true;
      });
    } catch (e) {
      debugPrint('File download failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: CustomText(text: 'Could not download this file.')),
      );
    }
  }

  /// Writes the downloaded copy into the device's public Downloads folder.
  Future<void> _handleSave() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await FileMessageService.downloadToCache(_url!, _fileName);
      final saved =
          await FileMessageService.saveToDownloads(file.path, _fileName);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: CustomText(
            text: saved != null
                ? 'Saved to Downloads'
                : 'Could not save the file. Check storage permission.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('File save failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: CustomText(text: 'Could not save the file.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final fileSize = widget.message.fileSize ?? 0;
    final sizeLabel = FileMessageService.formatFileSize(fileSize);
    final extLabel =
        FileMessageService.fileExtension(_fileName).toUpperCase();
    final type = FileMessageService.iconFor(_fileName);

    return GestureDetector(
      onTap: _handleTap,
      onLongPress: widget.onShowOptions,
      child: Container(
        width: 250.w,
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.14)
              : colors.surfaceDim.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type icon tile
            Container(
              width: 46.w,
              height: 46.w,
              decoration: BoxDecoration(
                color: widget.isMe
                    ? Colors.white.withValues(alpha: 0.25)
                    : colors.surface,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(type.icon,
                  color: type.color,
                  size: 26.sp),
            ),
            SizedBox(width: 10.w),
            // Name + size + actions
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    text: _fileName,
                    textColor: widget.textColor,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  if (sizeLabel.isNotEmpty)
                    CustomText(
                      text: extLabel.isNotEmpty
                          ? '$sizeLabel  •  $extLabel'
                          : sizeLabel,
                      textColor: widget.textColor.withValues(alpha: 0.6),
                      fontSize: 10.sp,
                    ),
                  SizedBox(height: 6.h),
                  if (_downloaded)
                    // Downloaded: Open button + a save-to-device icon.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _handleOpen,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 4.h,
                            ),
                            decoration: BoxDecoration(
                              color: widget.isMe
                                  ? Colors.white.withValues(alpha: 0.22)
                                  : colors.surface,
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(
                                color: widget.isMe
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : AppColors.primaryDark.withValues(alpha: 0.35),
                              ),
                            ),
                            child: _busy
                                ? Padding(
                                    padding: EdgeInsets.all(3.w),
                                    child: SizedBox(
                                      width: 12.w,
                                      height: 12.w,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: widget.isMe
                                            ? Colors.white
                                            : AppColors.primaryDark,
                                      ),
                                    ),
                                  )
                                : CustomText(
                                    text: 'Open',
                                    textColor: widget.isMe
                                        ? Colors.white
                                        : colors.textPrimary,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        GestureDetector(
                          onTap: _handleSave,
                          child: Container(
                            width: 26.w,
                            height: 26.w,
                            decoration: BoxDecoration(
                              color: widget.isMe
                                  ? Colors.white.withValues(alpha: 0.22)
                                  : colors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.isMe
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : AppColors.primaryDark.withValues(alpha: 0.35),
                              ),
                            ),
                            child: _busy
                                ? Padding(
                                    padding: EdgeInsets.all(5.w),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: widget.isMe
                                          ? Colors.white
                                          : AppColors.primaryDark,
                                    ),
                                  )
                                : Icon(Icons.save_alt_rounded,
                                    size: 16.sp,
                                    color: widget.isMe
                                        ? Colors.white
                                        : colors.textPrimary),
                          ),
                        ),
                      ],
                    )
                  else
                    // Not downloaded yet: only the download icon shows.
                    GestureDetector(
                      onTap: _handleDownload,
                      child: Container(
                        width: 26.w,
                        height: 26.w,
                        decoration: BoxDecoration(
                          color: widget.isMe
                              ? Colors.white.withValues(alpha: 0.22)
                              : colors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.isMe
                                ? Colors.white.withValues(alpha: 0.5)
                                : AppColors.primaryDark.withValues(alpha: 0.35),
                          ),
                        ),
                        child: _busy
                            ? Padding(
                                padding: EdgeInsets.all(5.w),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: widget.isMe
                                      ? Colors.white
                                      : AppColors.primaryDark,
                                ),
                              )
                            : Icon(Icons.download_rounded,
                                size: 16.sp,
                                color: widget.isMe
                                    ? Colors.white
                                    : colors.textPrimary),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
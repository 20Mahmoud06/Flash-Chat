import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/services/media/file_message_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'media_gallery_helpers.dart';

/// List of every file shared in the chat: attached documents (PDF, Word,
/// Excel, archives...) and audio files sent as attachments. Each row shows the
/// file-type icon, name, size and sender; tapping downloads it (once) and
/// opens it in the matching external app.
class MediaGalleryFilesTab extends StatelessWidget {
  final List<MessageModel> messages;
  final GallerySender sender;

  const MediaGalleryFilesTab({
    super.key,
    required this.messages,
    required this.sender,
  });

  @override
  Widget build(BuildContext context) {
    final files = messages
        .where((m) =>
            (m.messageType == MessageType.file ||
                m.messageType == MessageType.audio) &&
            (m.mediaUrls?.isNotEmpty ?? false))
        .toList();
    if (files.isEmpty) {
      return const MediaGalleryEmptyState(
        label: 'No files',
        icon: Icons.insert_drive_file_outlined,
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      itemCount: files.length,
      itemBuilder: (context, i) => _FileRow(message: files[i], sender: sender),
    );
  }
}

/// A single file entry with the same "download then open" behaviour as the
/// chat file bubble.
class _FileRow extends StatefulWidget {
  final MessageModel message;
  final GallerySender sender;

  const _FileRow({required this.message, required this.sender});

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
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

  Future<void> _checkDownloaded() async {
    final cached = await FileMessageService.cachedFile(_fileName);
    if (!mounted) return;
    setState(() => _downloaded = cached != null);
  }

  Future<void> _handleTap() async {
    if (_busy || _url == null) return;
    setState(() => _busy = true);
    try {
      await FileMessageService.downloadToCache(_url!, _fileName);
      if (!mounted) return;
      setState(() => _downloaded = true);
      final file = await FileMessageService.cachedFile(_fileName);
      if (file == null) throw Exception('Cached file missing');
      await FileMessageService.open(file.path);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      debugPrint('Gallery file open failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: CustomText(text: 'Could not open this file.')),
      );
    }
  }

  Future<void> _handleDownload() async {
    final url = _url;
    if (url == null || _busy) return;
    setState(() => _busy = true);
    try {
      await FileMessageService.downloadToCache(url, _fileName);
      if (!mounted) return;
      setState(() {
        _downloaded = true;
        _busy = false;
      });
    } catch (e) {
      debugPrint('Gallery file download failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: CustomText(text: 'Could not download this file.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final msg = widget.message;
    final type = FileMessageService.iconFor(_fileName);
    final extLabel = FileMessageService.fileExtension(_fileName).toUpperCase();
    final sizeLabel = FileMessageService.formatFileSize(msg.fileSize ?? 0);
    final isAudio = msg.messageType == MessageType.audio;

    final subtitle = <String>[
      if (sizeLabel.isNotEmpty) sizeLabel,
      if (extLabel.isNotEmpty) extLabel,
      if (isAudio && (msg.voiceDuration ?? 0) > 0)
        formatGalleryDuration(msg.voiceDuration!),
    ].join(' \u00b7 ');

    return Card(
      elevation: 1,
      margin: EdgeInsets.only(bottom: 10.h),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14.r),
        side: BorderSide(color: colors.divider),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
        leading: CircleAvatar(
          radius: 22.r,
          backgroundColor: type.color.withValues(alpha: 0.12),
          child: Icon(type.icon, color: type.color, size: 22.sp),
        ),
        title: CustomText(
          text: _fileName,
          fontSize: 15.sp,
          fontWeight: FontWeight.w600,
          textColor: colors.textPrimary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 2.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle.isNotEmpty)
                CustomText(
                  text: subtitle,
                  fontSize: 12.sp,
                  textColor: colors.textSecondary,
                ),
              SizedBox(height: 2.h),
              CustomText(
                text:
                    '${widget.sender.nameOf(msg)} \u00b7 ${formatGalleryTime(msg.timestamp)}',
                fontSize: 11.sp,
                textColor: colors.textWeak,
              ),
            ],
          ),
        ),
        trailing: _busy
            ? Padding(
                padding: EdgeInsets.all(4.w),
                child: SizedBox(
                  width: 18.w,
                  height: 18.w,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: type.color,
                  ),
                ),
              )
            : GestureDetector(
                onTap: _downloaded ? _handleTap : _handleDownload,
                child: Icon(
                  _downloaded ? Icons.open_in_new : Icons.download_rounded,
                  size: 20.sp,
                  color: type.color,
                ),
              ),
        onTap: _handleTap,
      ),
    );
  }
}

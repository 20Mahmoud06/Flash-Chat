import 'dart:io';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../cubit/chat_cubit.dart';
import '../media_preview_sheet/media_preview_sheet.dart';

/// Picks up to [kMaxPhotosPerMessage] images from the gallery and opens the
/// media preview sheet, sending them once the user confirms.
Future<void> pickComposerImages(BuildContext context, UserModel sender) async {
  final colors = FcAppColors.of(context);
  final assets = await AssetPicker.pickAssets(
    context,
    pickerConfig: AssetPickerConfig(
      maxAssets: kMaxPhotosPerMessage,
      requestType: RequestType.image,
      gridCount: 4,
      themeColor: colors.bubbleMine,
    ),
  );
  if (assets == null || assets.isEmpty) return;

  final files = <File>[];
  for (final asset in assets) {
    final file = (await asset.originFile) ?? (await asset.file);
    if (file != null) files.add(file);
  }
  if (!context.mounted || files.isEmpty) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => MediaPreviewSheet(
      images: files,
      onSend: (images, caption, videoDuration) {
        Navigator.pop(sheetContext);
        context
            .read<ChatCubit>()
            .sendImages(images, sender, caption: caption);
      },
    ),
  );
}

/// Captures a photo with the camera and opens the media preview sheet.
Future<void> takeComposerPhoto(BuildContext context, UserModel sender) async {
  final picker = ImagePicker();
  final photo = await picker.pickImage(source: ImageSource.camera);
  if (!context.mounted) return;
  if (photo == null) return;

  final file = File(photo.path);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => MediaPreviewSheet(
      images: [file],
      onSend: (images, caption, videoDuration) {
        Navigator.pop(sheetContext);
        context.read<ChatCubit>().sendImages(
              images,
              sender,
              caption: caption,
            );
      },
    ),
  );
}

/// Captures a video with the camera and opens the video preview.
Future<void> takeComposerVideo(BuildContext context, UserModel sender) async {
  try {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.camera);
    if (!context.mounted) return;
    if (video == null) return;

    await previewComposerVideo(context, File(video.path), sender);
  } catch (e) {
    debugPrint('Video capture failed: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: CustomText(text: 'Could not open recorded video.')),
    );
  }
}

/// Picks a video from the gallery and opens the video preview.
Future<void> pickComposerVideo(BuildContext context, UserModel sender) async {
  try {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery);
    if (!context.mounted) return;
    if (video == null) return;

    final file = File(video.path);
    await previewComposerVideo(context, file, sender);
  } catch (e) {
    debugPrint('Video pick failed: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: CustomText(text: 'Could not open this video.')),
    );
  }
}

/// Validates the video file (exists, ≤25MB) and opens the media preview
/// sheet, sending it once the user confirms.
Future<void> previewComposerVideo(
    BuildContext context, File file, UserModel sender) async {
  if (!await file.exists()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: CustomText(text: 'Could not read this video.')),
    );
    return;
  }

  final sizeBytes = await file.length();
  final sizeMB = sizeBytes / (1024 * 1024);

  if (sizeMB > 25) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: CustomText(text: 'Video must be ≤ 25MB')),
    );
    return;
  }

  if (!context.mounted) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => MediaPreviewSheet(
      images: const [],
      video: file,
      onSend: (images, caption, videoDuration) {
        Navigator.pop(sheetContext);
        context.read<ChatCubit>().sendVideo(
              file,
              sender,
              caption: caption,
              durationSeconds: videoDuration?.inSeconds,
            );
      },
    ),
  );
}

/// "Capture with camera" bottom sheet offering a photo or a video capture,
/// delegating each action to [onTakePhoto] / [onTakeVideo].
void showComposerCameraSheet(
  BuildContext context, {
  required VoidCallback onTakePhoto,
  required VoidCallback onTakeVideo,
}) {
  final colors = FcAppColors.of(context);
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 14.h, bottom: 6.h),
              child: Container(
                width: 40.w,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.surfaceDim,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: CustomText(
                text: 'Capture with camera',
                fontWeight: FontWeight.bold,
                fontSize: 16.sp,
                textColor: colors.textPrimary,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.avatarBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  color: Colors.lightBlueAccent,
                ),
              ),
              title: const CustomText(
                text: 'Take a Photo',
                fontWeight: FontWeight.w600,
              ),
              subtitle: CustomText(
                text: 'Capture a photo with your camera',
                fontSize: 12.sp,
                textColor: colors.textSecondary,
              ),
              onTap: () {
                Navigator.pop(ctx);
                onTakePhoto();
              },
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.avatarBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.videocam_outlined,
                  color: Colors.lightBlueAccent,
                ),
              ),
              title: const CustomText(
                text: 'Record a Video',
                fontWeight: FontWeight.w600,
              ),
              subtitle: CustomText(
                text: 'Record a video clip (max 25MB)',
                fontSize: 12.sp,
                textColor: colors.textSecondary,
              ),
              onTap: () {
                Navigator.pop(ctx);
                onTakeVideo();
              },
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    ),
  );
}
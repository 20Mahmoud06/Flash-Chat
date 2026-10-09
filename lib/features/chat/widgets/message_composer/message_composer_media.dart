import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/services/media/file_message_service.dart';
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
      onSend: (images, _, caption, __) {
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
      onSend: (images, _, caption, __) {
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

Future<void> takeComposerVideo(BuildContext context, UserModel sender) async {
  try {
    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.camera);
    if (!context.mounted) return;
    if (video == null) return;

    await previewComposerVideos(context, [File(video.path)], sender);
  } catch (e) {
    debugPrint('Video capture failed: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: CustomText(text: 'Could not open recorded video.')),
    );
  }
}

Future<void> pickComposerVideo(BuildContext context, UserModel sender) async {
  try {
    final colors = FcAppColors.of(context);
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: kMaxVideosPerMessage,
        requestType: RequestType.video,
        gridCount: 4,
        themeColor: colors.bubbleMine,
      ),
    );
    if (assets == null || assets.isEmpty || !context.mounted) return;

    final files = <File>[];
    final durations = <int?>[];
    for (final asset in assets) {
      final file = (await asset.originFile) ?? (await asset.file);
      if (file != null) {
        files.add(file);
        durations.add(asset.duration > 0 ? asset.duration : null);
      }
    }
    if (files.isEmpty || !context.mounted) return;

    await previewComposerVideos(context, files, sender,
        initialVideoDurations: durations);
  } catch (e) {
    debugPrint('Video pick failed: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: CustomText(text: 'Could not open these videos.')),
    );
  }
}

Future<void> previewComposerVideo(
    BuildContext context, File file, UserModel sender,
    {int? initialDuration}) {
  return previewComposerVideos(context, [file], sender,
      initialVideoDurations: [initialDuration]);
}

Future<void> previewComposerVideos(
  BuildContext context,
  List<File> files,
  UserModel sender, {
  List<int?>? initialVideoDurations,
}) async {
  if (files.isEmpty) return;

  final validFiles = <File>[];
  final validDurations = <int?>[];
  for (var i = 0; i < files.take(kMaxVideosPerMessage).length; i++) {
    final file = files[i];
    if (!await file.exists()) continue;
    if (await file.length() <= ChatCubit.maxFileSizeBytes) {
      validFiles.add(file);
      if (initialVideoDurations != null && i < initialVideoDurations.length) {
        validDurations.add(initialVideoDurations[i]);
      }
    }
  }

  if (validFiles.isEmpty || !context.mounted) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: CustomText(text: 'Could not read these videos.')),
      );
    }
    return;
  }

  if (files.length > kMaxVideosPerMessage) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: CustomText(
          text: 'Only the first $kMaxVideosPerMessage videos were added.',
        ),
      ),
    );
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => MediaPreviewSheet(
      videos: validFiles,
      initialVideoDurations: validDurations.isNotEmpty ? validDurations : null,
      onSend: (_, videos, caption, videoDurations) {
        Navigator.pop(sheetContext);
        context.read<ChatCubit>().sendVideos(
              videos,
              sender,
              caption: caption,
              videoDurations: videoDurations,
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
                text: 'Record a video clip (max 50MB)',
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

/// "Photos or video" chooser opened by the single media icon: passes through
/// to the exact same pickers as the previous separate photo / video buttons.
void showComposerMediaSheet(
  BuildContext context, {
  required VoidCallback onPickPhotos,
  required VoidCallback onPickVideo,
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
                text: 'Add media',
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
                  Icons.photo_library_outlined,
                  color: Colors.lightBlueAccent,
                ),
              ),
              title: const CustomText(
                text: 'Photos',
                fontWeight: FontWeight.w600,
              ),
              subtitle: CustomText(
                text: 'Pick photos from your gallery (up to $kMaxPhotosPerMessage)',
                fontSize: 12.sp,
                textColor: colors.textSecondary,
              ),
              onTap: () {
                Navigator.pop(ctx);
                onPickPhotos();
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
                text: 'Video',
                fontWeight: FontWeight.w600,
              ),
              subtitle: CustomText(
                text: 'Pick up to $kMaxVideosPerMessage videos from your gallery (max 50MB each)',
                fontSize: 12.sp,
                textColor: colors.textSecondary,
              ),
              onTap: () {
                Navigator.pop(ctx);
                onPickVideo();
              },
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    ),
  );
}

/// Opens the system file picker for the allowed file types: PDF / Word /
/// Excel documents and audio files. Audio sends as a playable audio message;
/// anything else sends as a document file message. Both are capped at the
/// app's upload limit.
Future<void> pickComposerFiles(BuildContext context, UserModel sender) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: FileMessageService.allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final path = picked.path;
    if (path == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: CustomText(text: 'Could not read this file.')),
      );
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: CustomText(text: 'Could not read this file.')),
      );
      return;
    }

    final sizeBytes = await file.length();
    if (sizeBytes > ChatCubit.maxFileSizeBytes) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: CustomText(text: 'File must be ≤ 50MB')),
      );
      return;
    }

    if (!context.mounted) return;
    await context.read<ChatCubit>().sendFile(file, sender, picked.name);
  } catch (e) {
    debugPrint('File pick failed: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: CustomText(text: 'Could not open this file.')),
    );
  }
}
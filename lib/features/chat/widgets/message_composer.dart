import 'dart:async';
import 'dart:io';
import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/features/connectivity/cubit/connectivity_cubit.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/services/connectivity/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/reply_preview.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../shared/widgets/voice_record_ui.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import 'media_preview_sheet.dart';
import 'reply_preview_card.dart';

class MessageComposer extends StatefulWidget {
  final String chatId;
  final bool isGroup;

  const MessageComposer(
      {super.key, required this.chatId, required this.isGroup});

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  UserModel? _sender;
  TextDirection _textDirection = TextDirection.ltr;
  bool _isRecording = false;
  StreamSubscription<int>? _offlineFeedbackSub;
  bool _feedbackSubscribed = false;

  /// Number of messages currently queued for auto-send while offline.
  int _pendingQueueCount = 0;

  /// Incremented on every offline send attempt so the shake animation
  /// re-triggers.
  int _shakeTick = 0;

  @override
  void initState() {
    super.initState();
    _loadSenderUser();
    _controller.addListener(_updateTextDirection);
    ConnectivityService.instance.isConnected
        .addListener(_onConnectivityChanged);
  }

  /// When the connection returns, the cubit auto-sends every queued
  /// message, so the "queued" chip must not show a stale count later.
  void _onConnectivityChanged() {
    if (!ConnectivityService.instance.isConnected.value) return;
    if (!mounted || _pendingQueueCount == 0) return;
    setState(() => _pendingQueueCount = 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_feedbackSubscribed) {
      _feedbackSubscribed = true;
      _offlineFeedbackSub = context
          .read<ChatCubit>()
          .offlineFeedbackStream
          .listen(_onOfflineQueued);
    }
  }

  /// Shown when the user tries to send while offline: shakes the send
  /// button, shows a pulsing icon, and a friendly in-app notification so
  /// they know the message is queued and will be sent automatically once
  /// the connection comes back.
  void _onOfflineQueued(int count) {
    if (!mounted) return;
    setState(() {
      _pendingQueueCount = count;
      // Only shake when the user is actually offline (a real "queued while
      // offline" event), not during the online auto-send flush that also
      // emits onto this stream while items succeed one by one.
      if (ConnectivityService.instance.isConnected.value) {
        _shakeTick = 0;
      } else {
        _shakeTick++;
      }
    });
  }

  /// Persistent "messages are queued" chip shown above the composer while
  /// the connection is missing, so users always know their messages are
  /// saved and will be sent automatically. Slides/fades in and out.
  Widget _buildPendingQueueChip() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axisAlignment: -1,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Container(
        key: ValueKey('queue_chip_$_pendingQueueCount'),
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Pulse(
              infinite: true,
              duration: const Duration(milliseconds: 1200),
              child: Icon(
                Icons.schedule_send_outlined,
                color: Colors.orange.shade700,
                size: 18,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: CustomText(
                text: _pendingQueueCount == 1
                    ? "1 message queued — will send automatically when "
                        "you're back online"
                    : '$_pendingQueueCount messages queued — will send '
                        'automatically when you\'re back online',
                fontSize: 12.sp,
                textColor: Colors.orange.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadSenderUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);

    // Server-first read falls back to the on-device cache when offline; if
    // that also fails (nothing cached), read straight from the local cache
    // so the composer can still queue messages for auto-send.
    DocumentSnapshot doc;
    try {
      doc = await userRef.get();
    } catch (_) {
      doc = await userRef.get(const GetOptions(source: Source.cache));
    }
    if (mounted) {
      setState(() {
        _sender = UserModel.fromFirestore(doc);
      });
    }
  }

  void _updateTextDirection() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _textDirection = intl.Bidi.detectRtlDirectionality(text)
            ? TextDirection.rtl
            : TextDirection.ltr;
      });
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _sender == null) return;

    context.read<ChatCubit>().sendMessage(text, _sender!);
    context.read<ChatCubit>().stopTyping();
    _controller.clear();
    _textDirection = TextDirection.ltr;
  }

  /// Fires on every keystroke: tells the cubit to publish (throttled) that
  /// we are typing, or to clear the flag once the field is emptied.
  void _onTypingChanged(String value) {
    final cubit = context.read<ChatCubit>();
    if (value.trim().isEmpty) {
      cubit.stopTyping();
    } else {
      cubit.updateTyping();
    }
  }

  Future<void> _pickImages() async {
    if (_sender == null) return;

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
    if (!mounted || files.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => MediaPreviewSheet(
        images: files,
        onSend: (images, caption, videoDuration) {
          Navigator.pop(sheetContext);
          context
              .read<ChatCubit>()
              .sendImages(images, _sender!, caption: caption);
        },
      ),
    );
  }

  Future<void> _takePhoto() async {
    if (_sender == null) return;

    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera);
    if (!mounted) return;
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
                _sender!,
                caption: caption,
              );
        },
      ),
    );
  }

  Future<void> _takeVideo() async {
    if (_sender == null) return;

    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(source: ImageSource.camera);
      if (!mounted) return;
      if (video == null) return;

      await _showVideoPreview(File(video.path));
    } catch (e) {
      debugPrint('Video capture failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open recorded video.')),
      );
    }
  }

  Future<void> _showVideoPreview(File file) async {
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read this video.')),
      );
      return;
    }

    final sizeBytes = await file.length();
    final sizeMB = sizeBytes / (1024 * 1024);

    if (sizeMB > 25) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video must be ≤ 25MB')),
      );
      return;
    }

    if (!mounted) return;

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
                _sender!,
                caption: caption,
                durationSeconds: videoDuration?.inSeconds,
              );
        },
      ),
    );
  }

  void _showCameraOptions() {
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
                  _takePhoto();
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
                  _takeVideo();
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleVoiceRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });
  }

  Future<void> _pickVideo() async {
    if (_sender == null) return;

    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (!mounted) return;
      if (video == null) return;

      final file = File(video.path);
      await _showVideoPreview(file);
    } catch (e) {
      debugPrint('Video pick failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this video.')),
      );
    }
  }

  @override
  void dispose() {
    ConnectivityService.instance.isConnected
        .removeListener(_onConnectivityChanged);
    _offlineFeedbackSub?.cancel();
    _controller.removeListener(_updateTextDirection);
    _controller.dispose();
    super.dispose();
  }

  /// Wraps the mic/send button so it shakes every time the user tries to
  /// send while offline. Plain when nothing has triggered it yet.
  Widget _buildSendAction(Widget button) {
    if (_shakeTick == 0) return button;
    return ShakeX(
      key: ValueKey('offline_shake_$_shakeTick'),
      duration: const Duration(milliseconds: 450),
      child: button,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        final colors = FcAppColors.of(context);
        final offline =
            context.select<ConnectivityCubit, bool>((c) => c.state.offline);
        MessageModel? replyingTo;
        String? replyingToSenderName;
        String? replyingToMediaUrl;
        int? replyingToMediaCount;

        final isUploading = state is ChatUploading;
        final uploadProgress = isUploading ? state.progress : 0.0;

        if (state is ChatLoaded) {
          replyingTo = state.replyingTo;
          replyingToSenderName = state.replyingToSenderName;
          replyingToMediaUrl = state.replyingToMediaUrl;
          replyingToMediaCount = state.replyingToMediaCount;
        }

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: colors.surface,
            boxShadow: [
              BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.3),
                  spreadRadius: 2,
                  blurRadius: 5),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyingTo != null)
                  Container(
                    padding: EdgeInsets.fromLTRB(6.w, 4.h, 6.w, 4.h),
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: colors.divider),
                    ),
                    margin: EdgeInsets.only(bottom: 8.h),
                    child: Row(
                      children: [
                        Expanded(
                          child: ReplyPreviewCard(
                            senderName: replyingToSenderName ?? 'Unknown',
                            type: replyingTo.messageType,
                            preview: replyPreviewString(replyingTo,
                                mediaCount: replyingToMediaCount),
                            mediaUrl: replyingToMediaUrl,
                            mediaCount: replyingToMediaCount,
                            duration: replyingTo.voiceDuration ??
                                replyingTo.videoDuration,
                            isOwnMessage: false,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.textSecondary),
                          onPressed: () {
                            context
                                .read<ChatCubit>()
                                .setReplyingTo(null, null, mediaUrl: null);
                          },
                        ),
                      ],
                    ),
                  ),
                if (isUploading)
                  LinearProgressIndicator(
                    value: uploadProgress,
                    minHeight: 3,
                    backgroundColor: colors.surfaceDim,
                    color: Colors.lightBlueAccent,
                  ),
                if (_pendingQueueCount > 0 && offline) _buildPendingQueueChip(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    /// Camera
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: const Icon(
                        Icons.camera_alt,
                        color: Colors.lightBlueAccent,
                        size: 22,
                      ),
                      onPressed: _showCameraOptions,
                    ),

                    /// Gallery
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: const Icon(
                        Icons.photo,
                        color: Colors.lightBlueAccent,
                        size: 22,
                      ),
                      onPressed: _pickImages,
                    ),

                    /// Video
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: const Icon(
                        Icons.videocam,
                        color: Colors.lightBlueAccent,
                        size: 22,
                      ),
                      onPressed: _pickVideo,
                    ),

                    /// Text OR Voice UI
                    Expanded(
                      child: _isRecording
                          ? VoiceRecordUI(
                              onSend: (file, duration) {
                                context.read<ChatCubit>().sendVoiceMessage(
                                      file,
                                      duration,
                                      _sender!,
                                    );
                                setState(() => _isRecording = false);
                              },
                              onCancel: () {
                                setState(() => _isRecording = false);
                              },
                            )
                          : Directionality(
                              textDirection: _textDirection,
                              child: TextField(
                                controller: _controller,
                                onChanged: _onTypingChanged,
                                keyboardType: TextInputType.multiline,
                                minLines: 1,
                                maxLines: 4,
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  height: 1.3,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12.w,
                                    vertical: 7.h,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20.r),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20.0.r),
                                    borderSide: BorderSide(
                                        color: Colors.lightBlue.shade100,
                                        width: 1.5.w),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20.0.r),
                                    borderSide: BorderSide(
                                        color: Colors.lightBlue.shade300,
                                        width: 1.5.w),
                                  ),
                                  filled: true,
                                  fillColor: colors.inputFill,
                                ),
                              ),
                            ),
                    ),

                    SizedBox(width: 2.w),

                    /// Mic / Send - Fully hidden while recording: VoiceRecordUI
                    /// already provides its own send & cancel controls, so
                    /// showing the composer's send button here too would draw a
                    /// second send icon behind/next to the recording one.
                    if (!_isRecording)
                      _buildSendAction(IconButton(
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 30, minHeight: 30),
                        icon: _controller.text.isEmpty
                            ? Icon(_isRecording ? Icons.close : Icons.mic,
                                color: Colors.lightBlueAccent)
                            : const Icon(
                                Icons.send,
                                color: Colors.lightBlueAccent,
                              ),
                        onPressed: _controller.text.isEmpty
                            ? _toggleVoiceRecording
                            : _sendMessage,
                      )),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

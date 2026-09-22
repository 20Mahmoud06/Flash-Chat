import 'dart:async';
import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/connectivity/cubit/connectivity_cubit.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/services/connectivity/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../core/theme/app_theme.dart';
import '../../cubit/chat_cubit.dart';
import '../../cubit/chat_state.dart';
import '../reply_preview.dart';
import '../voice_record_ui.dart';
import 'message_composer_media.dart';
import 'message_composer_pending_chip.dart';
import 'message_composer_reply_bar.dart';
import 'message_composer_upload_line.dart';

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

  /// When the connection returns, the bloc auto-sends every queued
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

  /// Fires on every keystroke: tells the bloc to publish (throttled) that
  /// we are typing, or to clear the flag once the field is emptied.
  void _onTypingChanged(String value) {
    final cubit = context.read<ChatCubit>();
    if (value.trim().isEmpty) {
      cubit.stopTyping();
    } else {
      cubit.updateTyping();
    }
  }

  Future<void> _pickImages() {
    final sender = _sender;
    if (sender == null) return Future.value();
    return pickComposerImages(context, sender);
  }

  Future<void> _takePhoto() {
    final sender = _sender;
    if (sender == null) return Future.value();
    return takeComposerPhoto(context, sender);
  }

  Future<void> _takeVideo() {
    final sender = _sender;
    if (sender == null) return Future.value();
    return takeComposerVideo(context, sender);
  }

  Future<void> _pickVideo() {
    final sender = _sender;
    if (sender == null) return Future.value();
    return pickComposerVideo(context, sender);
  }

  void _showCameraOptions() {
    showComposerCameraSheet(
      context,
      onTakePhoto: _takePhoto,
      onTakeVideo: _takeVideo,
    );
  }

  void _toggleVoiceRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });
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
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (replyingTo != null)
                      MessageComposerReplyBar(
                        senderName: replyingToSenderName ?? 'Unknown',
                        type: replyingTo.messageType,
                        preview: replyPreviewString(replyingTo,
                            mediaCount: replyingToMediaCount),
                        mediaUrl: replyingToMediaUrl,
                        mediaCount: replyingToMediaCount,
                        duration: replyingTo.voiceDuration ??
                            replyingTo.videoDuration,
                        onClose: () {
                          context
                              .read<ChatCubit>()
                              .setReplyingTo(null, null, mediaUrl: null);
                        },
                      ),
                    if (_pendingQueueCount > 0 && offline)
                      MessageComposerPendingQueueChip(
                          count: _pendingQueueCount),
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
                                        borderRadius:
                                            BorderRadius.circular(20.r),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(20.0.r),
                                        borderSide: BorderSide(
                                            color: Colors.lightBlue.shade100,
                                            width: 1.5.w),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(20.0.r),
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
                            constraints: const BoxConstraints(
                                minWidth: 30, minHeight: 30),
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
                if (isUploading)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: MessageComposerUploadProgressLine(
                      color: colors.bubbleMine,
                      progress: uploadProgress,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter/services.dart';
import '../../cubits/chat_cubit/chat_cubit.dart';
import '../../cubits/chat_cubit/chat_state.dart';
import '../../widgets/media_preview_sheet.dart';
import '../../widgets/voice_record_ui.dart';

class MessageComposer extends StatefulWidget {
  final String chatId;
  final bool isGroup;

  const MessageComposer({super.key, required this.chatId, required this.isGroup});

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}


class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  UserModel? _sender;
  TextDirection _textDirection = TextDirection.ltr;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _loadSenderUser();
    _controller.addListener(_updateTextDirection);
  }

  Future<void> _loadSenderUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
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
    _controller.clear();
    _textDirection = TextDirection.ltr;
  }

  Future<void> _pickImages() async {
    if (_sender == null) return;

    final picker = ImagePicker();
    final xfiles = await picker.pickMultiImage();

    if (xfiles.isEmpty) return;

    if (xfiles.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max 5 images allowed')),
      );
      return;
    }

    final files = xfiles.map((e) => File(e.path)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MediaPreviewSheet(
        images: files,
        onSend: (caption) {
          Navigator.pop(context);
          context
              .read<ChatCubit>()
              .sendImages(files, _sender!, caption: caption);
        },
      ),
    );
  }

  Future<void> _takePhoto() async {
    if (_sender == null) return;

    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;

    final file = File(photo.path);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MediaPreviewSheet(
        images: [file],
        onSend: (caption) {
          Navigator.pop(context);
          context.read<ChatCubit>().sendImages(
            [file],
            _sender!,
            caption: caption,
          );
        },
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

    final picker = ImagePicker();
    final video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    final file = File(video.path);
    final sizeMB = file.lengthSync() / (1024 * 1024);

    if (sizeMB > 25) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video must be ≤ 25MB')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MediaPreviewSheet(
        images: const [],
        video: file,
        onSend: (caption) {
          Navigator.pop(context);
          context.read<ChatCubit>().sendVideo(
            file,
            _sender!,
            caption: caption,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_updateTextDirection);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        MessageModel? replyingTo;
        String? replyingToSenderName;

        final isUploading = state is ChatUploading;
        final uploadProgress = isUploading ? state.progress : 0.0;

        if (state is ChatLoaded) {
          replyingTo = state.replyingTo;
          replyingToSenderName = state.replyingToSenderName;
        }

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
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
                    padding: EdgeInsets.all(8.w),
                    color: Colors.lightBlue.shade50,
                    child: Row(
                      children: [
                        Container(
                          width: 4.w,
                          height: 40.h,
                          color: Colors.lightBlueAccent,
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CustomText(
                                text: replyingToSenderName ?? 'Unknown',
                                fontWeight: FontWeight.bold,
                                textColor: Colors.lightBlueAccent,
                              ),
                              CustomText(
                                text: replyingTo.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            context.read<ChatCubit>().setReplyingTo(null, null);
                          },
                        ),
                      ],
                    ),
                  ),
                if (isUploading)
                  LinearProgressIndicator(
                    value: uploadProgress,
                    minHeight: 3,
                    backgroundColor: Colors.grey.shade300,
                    color: Colors.lightBlueAccent,
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    /// Camera
                    IconButton(
                      icon: const Icon(
                        Icons.camera_alt,
                        color: Colors.lightBlueAccent,
                      ),
                      onPressed: _takePhoto,
                    ),

                    /// Gallery
                    IconButton(
                      icon: const Icon(
                        Icons.photo,
                        color: Colors.lightBlueAccent,
                      ),
                      onPressed: _pickImages,
                    ),

                    /// Video
                    IconButton(
                      icon: const Icon(
                        Icons.videocam,
                        color: Colors.lightBlueAccent,
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
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
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
                            fillColor: Colors.grey.shade200,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(width: 4.w),

                    /// Mic / Send - Conditionally show only if not recording or text is not empty
                    if (!_isRecording || _controller.text.isNotEmpty)
                      IconButton(
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
                      ),
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
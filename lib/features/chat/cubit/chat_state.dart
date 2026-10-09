import 'package:equatable/equatable.dart';

import '../models/message_model.dart';

abstract class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object?> get props => [];
}

class ChatInitial extends ChatState {}

class ChatLoading extends ChatState {}

class ChatLoaded extends ChatState {
  final List<MessageModel> messages;
  final MessageModel? replyingTo;
  final String? replyingToSenderName;

  /// URL of the specific photo being replied to (null = whole group / text).
  final String? replyingToMediaUrl;

  /// Number of photos the reply targets (null = single photo / other media).
  final int? replyingToMediaCount;

  /// Index of the specific media item the reply targets (null = whole group).
  final int? replyingToMediaIndex;

  /// Whether older messages still exist in Firestore (pagination cursor).
  final bool hasMore;

  /// Whether a batch of older messages is currently being fetched.
  final bool loadingMore;

  const ChatLoaded(
    this.messages, {
    this.replyingTo,
    this.replyingToSenderName,
    this.replyingToMediaUrl,
    this.replyingToMediaCount,
    this.replyingToMediaIndex,
    this.hasMore = true,
    this.loadingMore = false,
  });

  @override
  List<Object?> get props => [
        messages,
        replyingTo,
        replyingToSenderName,
        replyingToMediaUrl,
        replyingToMediaCount,
        replyingToMediaIndex,
        hasMore,
        loadingMore,
      ];
}

class ChatUploading extends ChatState {
  final double progress;
  const ChatUploading(this.progress);

  /// [progress] MUST be part of [props]: bloc drops any state that equals the
  /// current one, and without it every `ChatUploading` compared equal — so only
  /// the very first progress value ever reached the UI and the composer's
  /// upload bar froze at 0% for the whole upload.
  @override
  List<Object?> get props => [progress];
}

class ChatError extends ChatState {
  final String message;

  const ChatError(this.message);

  @override
  List<Object> get props => [message];
}

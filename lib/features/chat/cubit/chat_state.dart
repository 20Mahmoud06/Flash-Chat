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
        hasMore,
        loadingMore,
      ];
}

class ChatUploading extends ChatState {
  final double progress;
  const ChatUploading(this.progress);
}

class ChatError extends ChatState {
  final String message;

  const ChatError(this.message);

  @override
  List<Object> get props => [message];
}
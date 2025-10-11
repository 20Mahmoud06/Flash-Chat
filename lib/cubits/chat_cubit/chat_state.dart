import 'package:equatable/equatable.dart';
import '../../models/message_model.dart';

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

  const ChatLoaded(
      this.messages, {
        this.replyingTo,
        this.replyingToSenderName,
      });

  @override
  List<Object?> get props => [messages, replyingTo, replyingToSenderName];
}

class ChatError extends ChatState {
  final String message;

  const ChatError(this.message);

  @override
  List<Object> get props => [message];
}
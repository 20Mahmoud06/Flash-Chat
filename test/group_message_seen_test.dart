import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/chat/widgets/message_bubble/group_message_seen.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UserModel user(String uid, String name) => UserModel(
        uid: uid,
        firstName: name,
        lastName: '',
        phoneNumber: '',
        email: '',
        avatarEmoji: '👤',
      );

  late DateTime sent;
  late MessageModel message;
  late Map<String, UserModel> members;
  late Map<String, Timestamp> joinTimestamps;

  setUp(() {
    sent = DateTime(2026, 9, 19, 12, 0, 0);
    message = MessageModel(
      id: 'm1',
      senderId: 'me',
      recipientId: 'group',
      text: 'hello',
      timestamp: Timestamp.fromDate(sent),
      status: 'sent',
    );
    members = {
      'me': user('me', 'Me'),
      'alice': user('alice', 'Alice'),
      'bob': user('bob', 'Bob'),
      'charlie': user('charlie', 'Charlie'),
    };
    joinTimestamps = {
      'me': Timestamp.fromDate(sent.subtract(const Duration(days: 1))),
      'alice': Timestamp.fromDate(sent.subtract(const Duration(days: 1))),
      'bob': Timestamp.fromDate(sent.subtract(const Duration(days: 1))),
      'charlie': Timestamp.fromDate(sent.subtract(const Duration(days: 1))),
    };
  });

  Map<String, Timestamp> lastSeen(Map<String, DateTime> seenAt) =>
      seenAt.map((uid, when) => MapEntry(uid, Timestamp.fromDate(when)));

  test('nobody has read the message: no seen-by entries', () {
    final seenBy = groupMessageSeenBy(
      message: message,
      members: members,
      memberLastSeen: lastSeen({}),
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );
    final total = groupMessageSeenTotal(
      message: message,
      members: members,
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );

    expect(seenBy, isEmpty);
    expect(total, 3); // alice, bob, charlie — the sender is excluded
  });

  test('a member who read it after the send time is counted as seen', () {
    final seenBy = groupMessageSeenBy(
      message: message,
      members: members,
      memberLastSeen: lastSeen({
        'alice': sent.add(const Duration(minutes: 5)),
      }),
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );

    expect(seenBy, hasLength(1));
    expect(seenBy.first.user.firstName, 'Alice');
    expect(seenBy.first.seenAt, sent.add(const Duration(minutes: 5)));
  });

  test('members whose lastSeen predates the message are not "seen"', () {
    final seenBy = groupMessageSeenBy(
      message: message,
      members: members,
      memberLastSeen: lastSeen({
        'alice': sent.add(const Duration(minutes: 5)),
        'bob': sent.subtract(const Duration(hours: 1)),
      }),
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );

    expect(seenBy.map((e) => e.user.firstName), ['Alice']);
  });

  test('members who joined after the message are excluded from seen AND total',
      () {
    joinTimestamps['charlie'] =
        Timestamp.fromDate(sent.add(const Duration(hours: 2)));
    final seenBy = groupMessageSeenBy(
      message: message,
      members: members,
      memberLastSeen: lastSeen({
        'alice': sent.add(const Duration(minutes: 5)),
        'bob': sent.add(const Duration(minutes: 6)),
        'charlie': sent.add(const Duration(hours: 3)),
      }),
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );
    final total = groupMessageSeenTotal(
      message: message,
      members: members,
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );

    expect(seenBy.map((e) => e.user.firstName), ['Alice', 'Bob']);
    expect(total, 2);
  });

  test('all present members read it: seenBy length equals total', () {
    final seenBy = groupMessageSeenBy(
      message: message,
      members: members,
      memberLastSeen: lastSeen({
        'alice': sent.add(const Duration(minutes: 1)),
        'bob': sent.add(const Duration(minutes: 1)),
        'charlie': sent.add(const Duration(minutes: 1)),
      }),
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );
    final total = groupMessageSeenTotal(
      message: message,
      members: members,
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );

    expect(seenBy, hasLength(3));
    expect(seenBy.length, total);
  });

  test('my own lastSeen never counts', () {
    final seenBy = groupMessageSeenBy(
      message: message,
      members: members,
      memberLastSeen: lastSeen({
        'me': sent.add(const Duration(minutes: 1)),
      }),
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );

    expect(seenBy, isEmpty);
  });

  test('group with a single other member: one read equals everyone', () {
    members.remove('bob');
    members.remove('charlie');
    joinTimestamps.remove('bob');
    joinTimestamps.remove('charlie');

    final seenBy = groupMessageSeenBy(
      message: message,
      members: members,
      memberLastSeen: lastSeen({'alice': sent.add(const Duration(minutes: 1))}),
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );
    final total = groupMessageSeenTotal(
      message: message,
      members: members,
      memberJoinTimestamps: joinTimestamps,
      myUid: 'me',
    );

    expect(seenBy, hasLength(1));
    expect(total, 1);
    expect(seenBy.length >= total, isTrue);
  });
}
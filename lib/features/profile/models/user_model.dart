import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String uid;
  final String email;
  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String avatarEmoji;
  final String? bio;
  final String? fcmToken;
  final List<String> blockedUids;
  final bool isDeleted;

  /// Whether the phone number was confirmed through the OTP flow.
  final bool phoneVerified;

  /// Whether the user lets others see their online/last-seen status.
  final bool presenceEnabled;

  /// Contact uid → nickname, visible only to this user. Set from the
  /// contact's info screen; used to override the contact's real name.
  final Map<String, String> nicknames;

  /// A placeholder user for when the actual user document is not found
  /// (e.g., deleted accounts). The avatar emoji is the red X.
  static UserModel get deletedUser => const UserModel(
    uid: 'deleted',
    email: 'deleted@example.com',
    firstName: 'Deleted',
    lastName: 'User',
    phoneNumber: '',
    avatarEmoji: '❌',
    isDeleted: true,
  );

  const UserModel({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    required this.avatarEmoji,
    this.bio,
    this.fcmToken,
    this.blockedUids = const [],
    this.isDeleted = false,
    this.phoneVerified = false,
    this.presenceEnabled = true,
    this.nicknames = const {},
  });

  /// Factory constructor to create a UserModel from a Firestore document.
  /// Returns [deletedUser] if the document does not exist.
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) {
      return UserModel.deletedUser;
    }

    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      avatarEmoji: data['avatarEmoji'] ?? '👤',
      bio: data['bio'] as String?,
      fcmToken: data['fcmToken'] as String?,
      blockedUids: List<String>.from(data['blockedUids'] ?? const []),
      isDeleted: data['isDeleted'] ?? false,
      phoneVerified: data['phoneVerified'] ?? false,
      presenceEnabled: data['presenceEnabled'] != false,
      nicknames: data['nicknames'] is Map
          ? (data['nicknames'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()))
          : const <String, String>{},
    );
  }

  /// Method to convert a UserModel instance into a Map for Firestore.
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'avatarEmoji': avatarEmoji,
      if (bio != null) 'bio': bio,
      if (fcmToken != null) 'fcmToken': fcmToken,
      'blockedUids': blockedUids,
      'phoneVerified': phoneVerified,
      'presenceEnabled': presenceEnabled,
      'nicknames': nicknames,
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? avatarEmoji,
    String? bio,
    String? fcmToken,
    List<String>? blockedUids,
    bool? isDeleted,
    bool? phoneVerified,
    bool? presenceEnabled,
    Map<String, String>? nicknames,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      bio: bio ?? this.bio,
      fcmToken: fcmToken ?? this.fcmToken,
      blockedUids: blockedUids ?? this.blockedUids,
      isDeleted: isDeleted ?? this.isDeleted,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      presenceEnabled: presenceEnabled ?? this.presenceEnabled,
      nicknames: nicknames ?? this.nicknames,
    );
  }

  String get fullName => '$firstName $lastName';

  /// Whether this document holds a real, completed profile. The FCM/HMS push
  /// services write a name-less shell doc (`{fcmTokens: [...]}`) the moment
  /// an auth account is created — before the OTP flow writes the real
  /// profile — so a document that exists but has an empty [firstName] must
  /// NOT be treated as a completed account.
  bool get isProfileComplete => firstName.isNotEmpty;

  @override
  List<Object?> get props => [uid, email, firstName, lastName, phoneNumber, avatarEmoji, bio, fcmToken, blockedUids, isDeleted, phoneVerified, presenceEnabled, nicknames];

}
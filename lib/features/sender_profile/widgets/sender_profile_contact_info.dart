import 'package:flutter/material.dart';
import '../../profile/models/user_model.dart';
import 'sender_profile_info_row.dart';

/// Phone, email and (when present) bio rows of the contact info screen.
class SenderProfileContactInfo extends StatelessWidget {
  final UserModel user;

  const SenderProfileContactInfo({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SenderProfileInfoRow(
          icon: Icons.phone_outlined,
          title: 'Phone',
          subtitle: user.phoneNumber,
          color: Colors.green,
        ),
        SenderProfileInfoRow(
          icon: Icons.email_outlined,
          title: 'Email',
          subtitle: user.email,
          color: Colors.orange,
        ),
        if (user.bio != null && user.bio!.isNotEmpty)
          SenderProfileInfoRow(
            icon: Icons.info_outline,
            title: 'Bio',
            subtitle: user.bio!,
            color: Colors.lightBlue,
          ),
      ],
    );
  }
}
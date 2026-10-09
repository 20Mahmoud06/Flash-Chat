import 'package:flutter/material.dart';
import '../../../core/utils/phone_formatter.dart';
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
          subtitle: formatPhoneForDisplay(user.phoneNumber),
          color: Colors.green,
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
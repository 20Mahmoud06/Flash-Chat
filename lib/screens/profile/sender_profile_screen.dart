import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SenderProfileScreen extends StatelessWidget {
  final UserModel user;
  const SenderProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: CustomText(
          text: "Contact Info",
              textColor: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20.sp),
        backgroundColor: Colors.lightBlueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 40.h),
            CircleAvatar(
              radius: 60.r,
              backgroundColor: Colors.lightBlue.shade50,
              child: CustomText(
                text: user.avatarEmoji,
                fontSize: 60.sp),
            ),
            SizedBox(height: 20.h),
            CustomText(
              text: '${user.firstName} ${user.lastName}',
              fontSize: 24.sp, fontWeight: FontWeight.bold
            ),
            SizedBox(height: 20.h),
            _buildInfoCard(
              icon: Icons.phone_outlined,
              title: "Phone",
              subtitle: user.phoneNumber,
              color: Colors.green,
            ),
            _buildInfoCard(
              icon: Icons.email_outlined,
              title: "Email",
              subtitle: user.email,
              color: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
      {required IconData icon,
        required String title,
        required String subtitle,
        required Color color}) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: CustomText(
            text: title,
            fontWeight: FontWeight.w600, textColor: Colors.grey.shade700),
        subtitle: CustomText(text: subtitle,fontSize: 15.sp),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flash_chat_app/widgets/custom_button.dart';
import '../core/routes/route_names.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../widgets/custom_text.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.0.h),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'logo',
                  child: SizedBox(
                    height: 60.0.h,
                    child: Image.asset('assets/logo.png'),
                  ),
                ),
                SizedBox(width: 10.w),
                DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 40.0.sp,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                  child: AnimatedTextKit(
                    isRepeatingAnimation: true,
                    repeatForever: true,
                    pause: const Duration(seconds: 3),
                    animatedTexts: [TypewriterAnimatedText('Flash Chat')],
                  ),
                ),
              ],
            ),
            SizedBox(height: 48.0.h),
            CustomButton(
              buttonColor: Colors.lightBlueAccent,
              onPressed: () {
                Navigator.pushReplacementNamed(context, RouteNames.login);
              },
              child: CustomText(
                text: 'Log In',
                fontSize: 18.sp,
                textColor: Colors.white,
              ),
            ),
            SizedBox(height: 20.h),
            CustomButton(
              buttonColor: Colors.blueAccent,
              onPressed: () {
                Navigator.pushReplacementNamed(context, RouteNames.signup);
              },
              child: CustomText(
                text:'Sign Up',
                fontSize: 18.sp,
                textColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
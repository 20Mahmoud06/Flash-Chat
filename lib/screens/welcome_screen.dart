import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/country_codes.dart';
import 'package:flash_chat_app/features/auth/cubit/auth_cubit.dart';
import 'package:flash_chat_app/models/phone_verification_arguments.dart';
import 'package:flash_chat_app/services/auth/pending_signup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/routes/route_names.dart';
import '../shared/widgets/custom_button.dart';
import '../shared/widgets/custom_text.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  PendingSignup? _pending;
  bool _signedInIncomplete = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _loadResumeState();
  }

  /// Detects an unfinished sign-up so the screen can offer to resume it:
  /// - auth account exists but no completed profile document → the user
  ///   closed the app on "Complete Profile" or the OTP verify screen.
  /// - a persisted OTP session → jump straight back to the verify screen.
  Future<void> _loadResumeState() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    PendingSignup? pending;
    var signedInIncomplete = currentUser != null;

    if (currentUser != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final data = doc.exists ? doc.data() : null;
        signedInIncomplete =
            !doc.exists || ((data?['firstName'] as String? ?? '').isEmpty);
      } catch (_) {
        // Offline and no cache: cannot tell, keep the resume options shown.
        signedInIncomplete = true;
      }
      try {
        pending = await PendingSignupService.instance.load();
      } catch (e) {
        // Corrupted/inaccessible resume state must never crash the auth
        // screen: simply offer the plain Sign In / Sign Up options.
        debugPrint('Failed to load pending signup: $e');
        pending = null;
      }
    }

    if (!mounted) return;
    setState(() {
      _pending = pending;
      _signedInIncomplete = signedInIncomplete;
      _checking = false;
    });
  }

  void _openLogin() {
    Navigator.pushReplacementNamed(context, RouteNames.login);
  }

  void _openSignup() {
    Navigator.pushReplacementNamed(context, RouteNames.signup);
  }

  void _continueSignUp() {
    Navigator.pushReplacementNamed(context, RouteNames.completeProfilePage);
  }

  void _resumeVerification() {
    final pending = _pending;
    if (pending == null) return;
    final country = CountryCodes.getByCode(pending.countryCode) ??
        CountryCodes.countries.first;
    Navigator.pushNamed(
      context,
      RouteNames.phoneVerificationPage,
      arguments: PhoneVerificationArguments(
        firstName: pending.firstName,
        lastName: pending.lastName,
        phoneNumber: pending.phoneNumber,
        country: country,
        otpId: pending.otpId,
      ),
    );
  }

  Future<void> _signOut() async {
    await PendingSignupService.instance.clear();
    if (!mounted) return;
    await context.read<AuthCubit>().logout();
    if (!mounted) return;
    setState(() {
      _pending = null;
      _signedInIncomplete = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Scaffold(
      backgroundColor: colors.surface,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.0.h),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
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
                              color: colors.textPrimary,
                            ),
                            child: AnimatedTextKit(
                              isRepeatingAnimation: true,
                              repeatForever: true,
                              pause: const Duration(seconds: 3),
                              animatedTexts: [
                                TypewriterAnimatedText('Flash Chat')
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 48.0.h),
                      if (!_checking && _signedInIncomplete) ...[
                        if (_pending != null)
                          CustomButton(
                            buttonColor: Colors.lightBlueAccent,
                            onPressed: _resumeVerification,
                            child: CustomText(
                              text: 'Verify Phone Number',
                              fontSize: 18.sp,
                              textColor: Colors.white,
                            ),
                          )
                        else
                          CustomButton(
                            buttonColor: Colors.lightBlueAccent,
                            onPressed: _continueSignUp,
                            child: CustomText(
                              text: 'Continue Sign Up',
                              fontSize: 18.sp,
                              textColor: Colors.white,
                            ),
                          ),
                        SizedBox(height: 20.h),
                      ],
                      CustomButton(
                        buttonColor: Colors.lightBlueAccent,
                        onPressed: _openLogin,
                        child: CustomText(
                          text: 'Log In',
                          fontSize: 18.sp,
                          textColor: Colors.white,
                        ),
                      ),
                      SizedBox(height: 20.h),
                      CustomButton(
                        buttonColor: Colors.blueAccent,
                        onPressed: _openSignup,
                        child: CustomText(
                          text: 'Sign Up',
                          fontSize: 18.sp,
                          textColor: Colors.white,
                        ),
                      ),
                      if (!_checking && _signedInIncomplete) ...[
                        SizedBox(height: 12.h),
                        Center(
                          child: CustomText(
                            text: 'Didn\'t finish signing up? Start fresh.',
                            fontSize: 12.sp,
                            textColor: colors.textWeak,
                          ),
                        ),
                        TextButton(
                          onPressed: _signOut,
                          child: CustomText(
                            text: 'Sign out',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                            textColor: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/country_codes.dart';
import 'package:flash_chat_app/features/auth/cubit/auth_cubit.dart';
import 'package:flash_chat_app/features/auth/models/phone_verification_arguments.dart';
import 'package:flash_chat_app/features/auth/services/auth.dart';
import 'package:flash_chat_app/features/auth/services/pending_signup_service.dart';
import 'package:flash_chat_app/services/otp/otp_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:quickalert/quickalert.dart';

import '../../../core/routes/route_names.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  PendingSignup? _pending;
  bool _signedInIncomplete = false;
  bool _checking = true;

  /// Guards the resume button while a replacement code is being emailed, so a
  /// double tap cannot send two codes.
  bool _resuming = false;

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
        final firstName = (data?['firstName'] as String? ?? '').trim();

        // The marker is the authoritative "this account still owes us
        // onboarding" signal (written at sign-up, cleared when the code is
        // verified). It is required here because the profile document is
        // written BEFORE the code is sent: someone who quit while waiting for
        // the code already has a name, so `firstName` alone would wrongly
        // hide the resume button from them and strand them on this screen
        // with nothing to tap.
        final onboardingPending =
            data?[AuthService.onboardingPendingField] == true;

        // RECOVERY. A fully set-up account (document exists, has a name, owes
        // no onboarding) has no business being on the auth screen — this is
        // exactly the account `AuthCubit.resolveSessionDestination` sends to
        // Home. If the splash's restore was slow, lost a race, or failed
        // outright, the user used to be stranded here while actually signed
        // in. Send them Home instead of making them sign in again.
        if (doc.exists && firstName.isNotEmpty && !onboardingPending) {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, RouteNames.homePage);
          return;
        }

        signedInIncomplete =
            !doc.exists || firstName.isEmpty || onboardingPending;
      } catch (_) {
        // Firestore unreachable (offline / permission / parse error).
        // Do NOT assume the profile is incomplete: the user may have a
        // perfectly good profile that we just can't read right now.
        // Showing "Continue Sign Up" here would confuse existing users
        // who are temporarily offline.  Keep signedInIncomplete = true
        // only if we know the user is genuinely logged-in (the initial
        // value), but suppress the resume buttons so we don't misroute.
        signedInIncomplete = false;
      }
      try {
        // Scoped to this account: a draft left behind by a different one must
        // never be offered here.
        pending = await PendingSignupService.instance.loadFor(currentUser.uid);
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

  /// Opens the profile form to finish the interrupted sign-up.
  ///
  /// Shares the [_resuming] guard with the verification resume: the button is
  /// shown in the same place for both, so a double tap must not push two
  /// copies of the profile screen onto the stack.
  void _continueSignUp() {
    if (_resuming) return;
    setState(() => _resuming = true);
    Navigator.pushReplacementNamed(context, RouteNames.completeProfilePage);
  }

  /// True when the stored draft got far enough to have a code waiting, i.e.
  /// the user already submitted their profile and only owes the OTP.
  ///
  /// Branches on the draft's STEP, not merely on it existing: a draft written
  /// the moment the account was created is non-null too, but has no phone
  /// number or session id yet, and sending that user to the verify screen
  /// would ask them for a code that was never sent.
  ///
  /// The phone number is required too, because without it no code can be sent
  /// or resent at all. That happens when the draft was lost — a reinstall, a
  /// wiped secure store, or signing up on a second device — while the account
  /// kept its `onboardingPending` marker in the cloud. In that case the user
  /// is offered "Continue Sign Up" instead, and the complete-profile screen
  /// is prefilled from the cloud document so they can just confirm and get a
  /// fresh code.
  bool get _awaitingOtp {
    final pending = _pending;
    if (pending == null || pending.step != PendingSignupStep.otp) return false;
    return pending.phoneNumber.trim().isNotEmpty;
  }

  Future<void> _resumeVerification() async {
    final pending = _pending;
    if (pending == null || !_awaitingOtp || _resuming) return;
    setState(() => _resuming = true);

    var otpId = pending.otpId;
    var codeWasRequested = false;

    try {
      // A code only lives a couple of minutes, so on a cold start the stored
      // session is usually gone or expired. `resendOtp` cannot refresh a dead
      // session, which used to leave the user staring at a verify screen whose
      // code could never work — so request a fresh one here instead. When the
      // session is still alive the emailed code is typed in as-is.
      if (!await OtpService().isSessionAlive(otpId: otpId)) {
        otpId = await OtpService().sendOtp(phone: pending.phoneNumber);
        codeWasRequested = true;
        final refreshed = pending.withOtp(
          otpId: otpId,
          phoneNumber: pending.phoneNumber,
          countryCode: pending.countryCode,
        );
        await PendingSignupService.instance.save(refreshed);
        if (!mounted) return;
        setState(() => _pending = refreshed);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _resuming = false);
      QuickAlert.show(
        context: context,
        type: QuickAlertType.error,
        title: "Couldn't Send Code",
        text: OtpService.otpErrorMessage(e),
        backgroundColor: FcAppColors.of(context).surface,
        headerBackgroundColor: FcAppColors.of(context).surface,
        titleColor: FcAppColors.of(context).textPrimary,
        textColor: FcAppColors.of(context).textSecondary,
      );
      return;
    }

    if (!mounted) return;
    setState(() => _resuming = false);

    if (codeWasRequested) {
      await QuickAlert.show(
        context: context,
        type: QuickAlertType.success,
        title: 'Code Sent',
        text: 'A new verification code is on its way to your email.',
        backgroundColor: FcAppColors.of(context).surface,
        headerBackgroundColor: FcAppColors.of(context).surface,
        titleColor: FcAppColors.of(context).textPrimary,
        textColor: FcAppColors.of(context).textSecondary,
      );
    }

    if (!mounted) return;
    // Prefer the country stored with the draft, then infer it from the number
    // itself. Falling straight to `countries.first` would show a random flag
    // for any legacy draft recorded before the country code was stored.
    final country = CountryCodes.getByCode(pending.countryCode) ??
        CountryCodes.countryForPhone(pending.phoneNumber) ??
        CountryCodes.getByCode('+20') ??
        CountryCodes.countries.first;
    Navigator.pushNamed(
      context,
      RouteNames.phoneVerificationPage,
      arguments: PhoneVerificationArguments(
        firstName: pending.firstName,
        lastName: pending.lastName,
        phoneNumber: pending.phoneNumber,
        country: country,
        otpId: otpId,
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
                        if (_awaitingOtp)
                          _resuming
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.lightBlueAccent),
                                )
                              : CustomButton(
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

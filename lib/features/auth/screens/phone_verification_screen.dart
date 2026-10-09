import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/page_transition.dart';
import 'package:flash_chat_app/features/auth/cubit/auth_cubit.dart';
import 'package:flash_chat_app/features/auth/widgets/otp_verification_header.dart';
import 'package:flash_chat_app/features/auth/widgets/resend_section.dart';
import 'package:flash_chat_app/features/home/screens/home_screen.dart';
import 'package:flash_chat_app/features/profile/cubit/profile_cubit.dart';
import 'package:flash_chat_app/features/profile/cubit/profile_state.dart';
import 'package:flash_chat_app/features/auth/models/phone_verification_arguments.dart';
import 'package:flash_chat_app/services/otp/otp_service.dart';
import 'package:flash_chat_app/features/auth/services/pending_signup_service.dart';
import 'package:flash_chat_app/features/profile/screens/complete_profile_screen.dart';
import 'package:flash_chat_app/shared/widgets/custom_button.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:otp_animated_fields/otp_animated_fields.dart';
import 'package:quickalert/quickalert.dart';

class PhoneVerificationScreen extends StatefulWidget {
  final PhoneVerificationArguments arguments;

  const PhoneVerificationScreen({super.key, required this.arguments});

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  static const int _maxResends = 3;

  final OtpAnimatedController _otpController = OtpAnimatedController();
  final FocusNode _otpFocusNode = FocusNode();
  final OtpService _otpService = OtpService();

  /// Current OTP session id (starts from the one created at signup; reused
  /// by resend since the service keeps the same session).
  late String _otpId;

  Timer? _countdownTimer;

  /// Resend countdown state is restored from the Firestore OTP document (see
  /// [OtpSessionStatus]) so it survives widget rebuilds, leaving/re-entering
  /// the screen, app backgrounding and app restarts.
  DateTime? _nextResendAt;
  int _countdown = 0;
  int _resendCount = 0;

  bool _isVerifying = false;
  bool _isResending = false;
  bool _showError = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _otpId = widget.arguments.otpId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _otpFocusNode.requestFocus();
    });
    _loadOtpState();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  /// Reloads the stored session (resend count + cooldown) from Firestore and
  /// resumes the countdown from the stored timestamp instead of restarting a
  /// fresh timer. Falls back to a fresh countdown if the state cannot load.
  Future<void> _loadOtpState() async {
    try {
      final status = await _otpService.getOtpStatus(otpId: _otpId);
      if (!mounted) return;
      setState(() {
        _nextResendAt = status.nextResendAt;
        _resendCount = status.resendCount;
        _countdown = status.secondsUntilNextResend;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nextResendAt = null;
        _resendCount = 0;
        _countdown = 0;
      });
    } finally {
      if (mounted) {
        _startCountdown();
      }
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = _nextResendAt;
      final remaining =
          next == null ? 0 : next.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown = remaining);
      }
    });
  }

  bool get _canResend => _countdown == 0 && _resendCount < _maxResends;

  Future<void> _verifyCode() async {
    if (_isVerifying) return;
    final code = _otpController.text.trim();
    if (code.length < 6) {
      setState(() {
        _showError = true;
        _errorText = 'Please enter the 6-digit code';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _showError = false;
      _errorText = null;
    });

    // Move the boxes into the orbit while verification runs.
    _otpController.verify();

    try {
      final verified = await _otpService.verifyOtp(
        otpId: _otpId,
        code: code,
      );
      if (!mounted) return;

      if (!verified) {
        if (_isVerifying) {
          setState(() => _isVerifying = false);
        }
        setState(() {
          _showError = true;
          _errorText = 'Invalid code. Please check the code and try again.';
        });
        _otpController.fail();
        return;
      }

      // Code was correct: collapse the boxes into the success check mark.
      _otpController.succeed();

      await _completeProfile();

      // Success/navigation is driven by the BlocConsumer listener.
      if (mounted && _isVerifying) {
        setState(() => _isVerifying = false);
      }
    } catch (e) {
      if (!mounted) return;
      if (_isVerifying) {
        setState(() => _isVerifying = false);
      }
      setState(() {
        _showError = true;
        _errorText = OtpService.otpErrorMessage(e);
      });
      _otpController.fail();
    }
  }

  Future<void> _completeProfile() async {
    // Complete phone verification and update Firebase Auth. The bloc itself
    // guards against a stalled Firestore transaction (timeout → ProfileError)
    // so the UI never stays on the loading spinner; its ProfileUpdateSuccess /
    // ProfileError states are handled by the BlocConsumer below.
    await context.read<ProfileCubit>().completePhoneVerification(
          firstName: widget.arguments.firstName,
          lastName: widget.arguments.lastName,
          phoneNumber: widget.arguments.phoneNumber,
        );

    // Refresh auth status to ensure the user is properly logged in
    if (mounted) {
      context.read<AuthCubit>().checkAuthStatus();
    }
  }

  /// Sends the user back to the profile form to correct the phone number.
  ///
  /// The form is prefilled from the cloud document, and submitting it sends a
  /// fresh code, so this is a clean re-run of the last step rather than a dead
  /// end.
  ///
  /// The stored draft is first rewound to the PROFILE step, dropping the dead
  /// OTP session and the number we are abandoning. Without this the account
  /// would still look like it was waiting on a code: quitting the form and
  /// reopening the app would offer "Verify Phone Number" again, pointing at the
  /// very number the user just rejected.
  Future<void> _changeNumber() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null &&
          await PendingSignupService.instance.loadFor(uid) != null) {
        await PendingSignupService.instance.save(PendingSignup.atProfile(
          uid: uid,
          firstName: widget.arguments.firstName,
          lastName: widget.arguments.lastName,
        ));
      }
    } catch (e) {
      // Not fatal: the form is prefilled from the cloud document anyway, and a
      // stale draft would only cost a less specific resume button.
      debugPrint('Could not rewind onboarding draft: $e');
    }
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const CompleteProfileScreen(),
        transitionsBuilder: PageTransition.slideFromRight,
      ),
    );
  }

  Future<void> _resendCode() async {
    if (_isResending || !_canResend) return;
    setState(() => _isResending = true);

    try {
      // A live session keeps its id and simply gets a new code, which keeps
      // the resend cooldown and budget meaningful.
      //
      // A dead session (expired, or deleted after too many wrong attempts)
      // cannot be resend-refreshed at all — `resendOtp` refuses without the
      // document — and the code only lives a couple of minutes, so this is
      // the normal case for a user who wandered off. Minting a fresh session
      // for the same number is what stops them being stranded on a verify
      // screen whose code can no longer be replaced.
      if (await _otpService.isSessionAlive(otpId: _otpId)) {
        // The same OTP session id is reused on resend: a fresh code is
        // emailed but the same otpId stays valid for verification.
        await _otpService.resendOtp(otpId: _otpId);
      } else {
        final newOtpId = await _otpService.sendOtp(
          phone: widget.arguments.phoneNumber,
        );
        _otpId = newOtpId;
        await _persistDraft(newOtpId);
      }
      if (!mounted) return;

      setState(() {
        _isResending = false;
        _showError = false;
        _errorText = null;
      });
      _otpController.reset();
      _otpFocusNode.requestFocus();
      await _loadOtpState();
      if (!mounted) return;
      _showQuickAlert(
        context,
        type: QuickAlertType.success,
        title: 'Code Resent',
        text: 'A new verification code has been sent.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResending = false);
      _showQuickAlert(
        context,
        type: QuickAlertType.error,
        title: 'Resend Failed',
        text: OtpService.otpErrorMessage(e),
      );
    }
  }

  /// Keeps the local onboarding draft pointing at the session that is
  /// actually on screen, so a cold start resumes against the live code
  /// instead of one that has already been replaced.
  Future<void> _persistDraft(String otpId) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;
    try {
      await PendingSignupService.instance.save(PendingSignup(
        uid: authUser.uid,
        step: PendingSignupStep.otp,
        firstName: widget.arguments.firstName,
        lastName: widget.arguments.lastName,
        phoneNumber: widget.arguments.phoneNumber,
        countryCode: widget.arguments.country.code,
        otpId: otpId,
      ));
    } catch (e) {
      // Losing the draft only costs the ability to resume later.
      debugPrint('Could not update onboarding draft: $e');
    }
  }

  OtpAnimatedTheme _buildAnimatedTheme(bool isDark) {
    final colors = FcAppColors.of(context);
    return OtpAnimatedTheme.light(
      accentColor: Colors.lightBlueAccent,
    ).copyWith(
      fillColor: colors.surface,
      borderColor:
          isDark ? Colors.lightBlue.shade300 : Colors.lightBlue.shade200,
      borderWidth: 1.5.w,
      borderRadius: 14.r,
      boxSize: 48.w,
      textStyle: TextStyle(
        color: colors.textPrimary,
        fontSize: 22.sp,
        fontWeight: FontWeight.bold,
      ),
      keyboardAppearance: isDark ? Brightness.dark : Brightness.light,
      errorColor: Theme.of(context).colorScheme.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: const CustomText(
            text: 'Verify Phone Number',
            textColor: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          centerTitle: true,
          backgroundColor: Colors.lightBlueAccent,
        ),
        backgroundColor: colors.surface,
        body: BlocConsumer<ProfileCubit, ProfileState>(
          listener: (context, state) {
            if (state is ProfileUpdateSuccess) {
              // Verification finished: the account is complete, so the
              // stored draft is dead weight and must not offer to resume.
              PendingSignupService.instance.clear();
              _showQuickAlert(
                context,
                type: QuickAlertType.success,
                title: 'Phone Verified!',
                text: 'Welcome aboard!',
                barrierDismissible: false,
                onConfirmBtnTap: () {
                  // Capture the navigator BEFORE dismissing the dialog. Using
                  // `context` after the pop is a use-after-dispose hazard: if
                  // the dialog route is gone, that context is defunct and the
                  // navigation silently does nothing — leaving the user on a
                  // verified account that never reaches Home.
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  if (!mounted) return;
                  navigator.pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          const HomeScreen(),
                      transitionsBuilder: PageTransition.slideFromRight,
                    ),
                  );
                },
              );
            }
            if (state is ProfileError) {
              _showQuickAlert(
                context,
                type: QuickAlertType.error,
                title: 'Verification Failed',
                text: state.message,
              );
            }
          },
          builder: (context, state) {
            final isSavingProfile = state is ProfileLoading;
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 32.h),
                child: Column(
                  children: [
                    const OtpVerificationHeader(),
                    OtpAnimatedField(
                      length: 6,
                      controller: _otpController,
                      focusNode: _otpFocusNode,
                      autofocus: true,
                      enabled: !_isVerifying && !isSavingProfile,
                      keyboardType: TextInputType.number,
                      theme: _buildAnimatedTheme(isDark),
                      onChanged: (_) {
                        if (_showError) {
                          setState(() {
                            _showError = false;
                            _errorText = null;
                          });
                        }
                      },
                      onCompleted: (_) => _verifyCode(),
                      onFailed: (_) => _otpFocusNode.requestFocus(),
                    ),
                    if (_showError && _errorText != null)
                      Padding(
                        padding: EdgeInsets.only(top: 12.h),
                        child: Text(
                          _errorText!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 14.sp,
                          ),
                        ),
                      ),
                    SizedBox(height: 32.h),
                    CustomButton(
                      onPressed: () {
                        if (isSavingProfile) return;
                        _verifyCode();
                      },
                      buttonColor: Colors.lightBlueAccent,
                      child: CustomText(
                        text: 'Verify',
                        textColor: Colors.white,
                        fontSize: 18.sp,
                      ),
                    ),
                    SizedBox(height: 20.h),
                    ResendSection(
                      resendCount: _resendCount,
                      maxResends: _maxResends,
                      isResending: _isResending,
                      countdown: _countdown,
                      canResend: _canResend,
                      onResend: _resendCode,
                    ),
                    SizedBox(height: 12.h),
                    // Escape hatch for a mistyped or unreachable number. Resend
                    // cannot help there (the code never arrives), and the cloud
                    // `onboardingPending` marker keeps the account out of Home
                    // until a code is verified — so without this the user would
                    // be trapped on this screen with no way to correct it.
                    TextButton(
                      onPressed: isSavingProfile ? null : _changeNumber,
                      child: CustomText(
                        text: 'Wrong number? Change it',
                        textColor: Colors.lightBlueAccent,
                        fontSize: 14.sp,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

void _showQuickAlert(
  BuildContext context, {
  required QuickAlertType type,
  required String title,
  required String text,
  bool barrierDismissible = true,
  VoidCallback? onConfirmBtnTap,
}) {
  final colors = FcAppColors.of(context);
  QuickAlert.show(
    context: context,
    type: type,
    title: title,
    text: text,
    barrierDismissible: barrierDismissible,
    backgroundColor: colors.surface,
    headerBackgroundColor: colors.surface,
    titleColor: colors.textPrimary,
    textColor: colors.textSecondary,
    onConfirmBtnTap: onConfirmBtnTap,
  );
}

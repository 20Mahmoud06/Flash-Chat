import 'dart:async';
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
      final remaining = next == null
          ? 0
          : next.difference(DateTime.now()).inSeconds;
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

  Future<void> _resendCode() async {
    if (_isResending || !_canResend) return;
    setState(() => _isResending = true);

    try {
      // The same OTP session id is reused on resend: a fresh code is emailed
      // but the same otpId stays valid for verification. The new cooldown and
      // resend count are read back from Firestore so they persist.
      await _otpService.resendOtp(otpId: _otpId);
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
                // Verification finished: the account is complete, no more
                // resume point needed.
                PendingSignupService.instance.clear();
                _showQuickAlert(
                  context,
                  type: QuickAlertType.success,
                  title: 'Phone Verified!',
                  text: 'Welcome aboard!',
                  barrierDismissible: false,
                  onConfirmBtnTap: () {
                    Navigator.of(context, rootNavigator: true).pop();
                    Navigator.pushReplacement(
                      context,
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
                  padding:
                      EdgeInsets.symmetric(horizontal: 24.w, vertical: 32.h),
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
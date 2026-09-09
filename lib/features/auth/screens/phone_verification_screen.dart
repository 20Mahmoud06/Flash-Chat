import 'dart:async';

import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/page_transition.dart';
import 'package:flash_chat_app/features/auth/cubit/auth_cubit.dart';
import 'package:flash_chat_app/features/chat/screens/home_screen.dart';
import 'package:flash_chat_app/features/profile/cubit/profile_cubit.dart';
import 'package:flash_chat_app/features/profile/cubit/profile_state.dart';
import 'package:flash_chat_app/models/phone_verification_arguments.dart';
import 'package:flash_chat_app/services/otp/otp_service.dart';
import 'package:flash_chat_app/services/auth/pending_signup_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_button.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:pinput/pinput.dart';
import 'package:quickalert/quickalert.dart';

class PhoneVerificationScreen extends StatefulWidget {
  final PhoneVerificationArguments arguments;

  const PhoneVerificationScreen({super.key, required this.arguments});

  @override
  State<PhoneVerificationScreen> createState() => _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  static const int _resendCooldownSeconds = 30;
  static const int _maxResends = 3;

  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();
  final OtpService _otpService = OtpService();

  /// Current OTP session id (starts from the one created at signup; reused
  /// by resend since the service keeps the same session).
  late String _otpId;

  Timer? _countdownTimer;
  int _countdown = _resendCooldownSeconds;
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
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = _resendCooldownSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown -= 1);
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

    try {
      final verified = await _otpService.verifyOtp(
        otpId: _otpId,
        code: code,
      );
      if (!mounted) return;

      if (!verified) {
        setState(() {
          _isVerifying = false;
          _showError = true;
          _errorText = 'Invalid code. Please check the code and try again.';
        });
        _otpController.clear();
        _otpFocusNode.requestFocus();
        _showWrongCodeMessage();
        return;
      }

      await _completeProfile();

      // Stop the spinner once profile completion has resolved (whether it
      // succeeded or the cubit emitted an error). Success/navigation is driven
      // by the BlocConsumer listener.
      if (mounted && _isVerifying) {
        setState(() => _isVerifying = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _showError = true;
        _errorText = OtpService.otpErrorMessage(e);
      });
    }
  }

  /// Shows a QuickAlert (same package used for resend) when the entered code
  /// does not match. Keeps the existing inline pinput error too.
  void _showWrongCodeMessage() {
    QuickAlert.show(
      context: context,
      type: QuickAlertType.error,
      title: 'Incorrect Code',
      text: 'The code you entered is incorrect. Please try again or resend a new code.',
      backgroundColor: FcAppColors.of(context).surface,
      headerBackgroundColor: FcAppColors.of(context).surface,
      titleColor: FcAppColors.of(context).textPrimary,
      textColor: FcAppColors.of(context).textSecondary,
    );
  }

  Future<void> _completeProfile() async {
    // Complete phone verification and update Firebase Auth. The cubit itself
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
      // The same OTP session id is reused on resend: a fresh code is shown
      // in a notification but the same otpId stays valid for verification.
      await _otpService.resendOtp(otpId: _otpId);
      if (!mounted) return;

      setState(() {
        _isResending = false;
        _resendCount += 1;
        _showError = false;
        _errorText = null;
      });
      _otpController.clear();
      _otpFocusNode.requestFocus();
      _startCountdown();
      QuickAlert.show(
        context: context,
        type: QuickAlertType.success,
        title: 'Code Resent',
        text: 'A new verification code has been sent.',
        backgroundColor: FcAppColors.of(context).surface,
        headerBackgroundColor: FcAppColors.of(context).surface,
        titleColor: FcAppColors.of(context).textPrimary,
        textColor: FcAppColors.of(context).textSecondary,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isResending = false);
      QuickAlert.show(
        context: context,
        type: QuickAlertType.error,
        title: 'Resend Failed',
        text: OtpService.otpErrorMessage(e),
        backgroundColor: FcAppColors.of(context).surface,
        headerBackgroundColor: FcAppColors.of(context).surface,
        titleColor: FcAppColors.of(context).textPrimary,
        textColor: FcAppColors.of(context).textSecondary,
      );
    }
  }

  PinTheme _buildPinTheme(BoxConstraints constraints, bool isDark) {
    final colors = FcAppColors.of(context);
    final size = constraints.maxWidth < 320.w ? 46.w : 48.w;
    return PinTheme(
      width: size,
      height: 58.h,
      textStyle: TextStyle(
        color: colors.textPrimary,
        fontSize: 22.sp,
        fontWeight: FontWeight.bold,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isDark ? Colors.lightBlue.shade300 : Colors.lightBlue.shade200,
          width: 1.5.w,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocProvider(
      create: (context) => ProfileCubit(),
      child: GestureDetector(
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
                QuickAlert.show(
                  context: context,
                  type: QuickAlertType.success,
                  title: 'Phone Verified!',
                  text: 'Welcome aboard!',
                  barrierDismissible: false,
                  backgroundColor: FcAppColors.of(context).surface,
                  headerBackgroundColor: FcAppColors.of(context).surface,
                  titleColor: FcAppColors.of(context).textPrimary,
                  textColor: FcAppColors.of(context).textSecondary,
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
                QuickAlert.show(
                  context: context,
                  type: QuickAlertType.error,
                  title: 'Verification Failed',
                  text: state.message,
                  backgroundColor: FcAppColors.of(context).surface,
                  headerBackgroundColor: FcAppColors.of(context).surface,
                  titleColor: FcAppColors.of(context).textPrimary,
                  textColor: FcAppColors.of(context).textSecondary,
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
                      SizedBox(height: 24.h),
                      Container(
                        width: 96.w,
                        height: 96.w,
                        decoration: BoxDecoration(
                          color: colors.avatarBackground,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.sms_outlined,
                          size: 44.w,
                          color: Colors.lightBlueAccent,
                        ),
                      ),
                      SizedBox(height: 24.h),
                      CustomText(
                        text: 'Enter the 6-digit code',
                        textColor: colors.textPrimary,
                        fontSize: 22.sp,
                        fontWeight: FontWeight.bold,
                      ),
                      SizedBox(height: 8.h),
                      CustomText(
                        text:
                            'We sent a verification code\nin a notification',
                        textAlign: TextAlign.center,
                        textColor: colors.textSecondary,
                        fontSize: 15.sp,
                      ),
                      SizedBox(height: 32.h),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final defaultTheme = _buildPinTheme(constraints, isDark);
                          return Pinput(
                            length: 6,
                            controller: _otpController,
                            focusNode: _otpFocusNode,
                            autofocus: true,
                            enabled: !_isVerifying && !isSavingProfile,
                            keyboardType: TextInputType.number,
                            hapticFeedbackType: HapticFeedbackType.lightImpact,
                            forceErrorState: _showError,
                            errorText: _errorText,
                            errorTextStyle: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 14.sp,
                            ),
                            onClipboardFound: (value) {
                              if (value.length == 6) _verifyCode();
                            },
                            onChanged: (_) {
                              if (_showError) {
                                setState(() {
                                  _showError = false;
                                  _errorText = null;
                                });
                              }
                            },
                            onCompleted: (_) => _verifyCode(),
                            defaultPinTheme: defaultTheme,
                            focusedPinTheme: defaultTheme.copyWith(
                              decoration: defaultTheme.decoration!.copyWith(
                                border: Border.all(
                                  color: Colors.lightBlueAccent,
                                  width: 2.0.w,
                                ),
                              ),
                            ),
                            errorPinTheme: defaultTheme.copyWith(
                              decoration: defaultTheme.decoration!.copyWith(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.error,
                                  width: 2.0.w,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 32.h),
                      if (_isVerifying || isSavingProfile)
                        const Center(
                          child: CircularProgressIndicator(
                            color: Colors.lightBlueAccent,
                          ),
                        )
                      else
                        CustomButton(
                          onPressed: () => _verifyCode(),
                          buttonColor: Colors.lightBlueAccent,
                          child: CustomText(
                            text: 'Verify',
                            textColor: Colors.white,
                            fontSize: 18.sp,
                          ),
                        ),
                      SizedBox(height: 20.h),
                      _buildResendSection(colors),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResendSection(FcAppColors colors) {
    if (_resendCount >= _maxResends) {
      return CustomText(
        text: 'Too many resend attempts. Please try again later.',
        textColor: colors.textWeak,
        fontSize: 14.sp,
        textAlign: TextAlign.center,
      );
    }

    return Column(
      children: [
        CustomText(
          text: "Didn't receive the code?",
          textColor: colors.textSecondary,
          fontSize: 14.sp,
        ),
        SizedBox(height: 4.h),
        if (_isResending)
          const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.lightBlueAccent,
            ),
          )
        else if (_canResend)
          TextButton(
            onPressed: _resendCode,
            child: CustomText(
              text: 'Resend code',
              textColor: Colors.lightBlueAccent,
              fontSize: 15.sp,
              fontWeight: FontWeight.bold,
            ),
          )
        else
          CustomText(
            text: 'Resend code in ${_countdown}s',
            textColor: colors.textWeak,
            fontSize: 14.sp,
          ),
      ],
    );
  }
}
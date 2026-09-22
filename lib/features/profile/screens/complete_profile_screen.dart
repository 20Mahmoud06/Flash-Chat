import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/auth/widgets/phone_number_field.dart';
import 'package:flash_chat_app/features/auth/models/phone_verification_arguments.dart';
import 'package:flash_chat_app/features/auth/services/phone_registry.dart';
import 'package:flash_chat_app/features/auth/services/pending_signup_service.dart';
import 'package:flash_chat_app/services/otp/otp_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_button.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flash_chat_app/shared/widgets/custom_text_form_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:quickalert/quickalert.dart';
import '../../../core/routes/route_names.dart';
import '../models/user_model.dart';

class CompleteProfileScreen extends StatefulWidget {
  final UserModel? user;

  const CompleteProfileScreen({super.key, this.user});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final OtpService _otpService = OtpService();

  bool _sendingOtp = false;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    // Pre-fill the name fields once from the Google/email account. This
    // must not run again afterwards: didChangeDependencies would re-fire
    // on every dependency change (e.g. the keyboard opening) and overwrite
    // whatever the user has typed.
    final authUser = FirebaseAuth.instance.currentUser;
    if (widget.user != null && widget.user!.firstName.isNotEmpty) {
      _firstNameController.text = widget.user!.firstName;
      _lastNameController.text = widget.user!.lastName;
    } else if (authUser != null &&
        authUser.displayName != null &&
        authUser.displayName!.isNotEmpty) {
      final names = authUser.displayName!.split(' ');
      _firstNameController.text = names.isNotEmpty ? names.first : '';
      _lastNameController.text =
          names.length > 1 ? names.sublist(1).join(' ') : '';
    }

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  String _getErrorMessage(dynamic error) {
    return OtpService.otpErrorMessage(error);
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_sendingOtp) return;

    setState(() => _sendingOtp = true);
    try {
      final phoneNumberField = _phoneFieldKey.currentState!;
      final e164Phone = phoneNumberField.e164PhoneNumber;

      // Reject numbers that are already registered before sending an SMS.
      // Deleted-account tombstones (isDeleted == true) don't count, so the
      // phone can be reused after an account is deleted.
      if (await PhoneRegistry.instance.isPhoneInUse(e164Phone)) {
        throw 'This phone number is already registered.';
      }

      final otpId = await _otpService.sendOtp(phone: e164Phone);
      if (!mounted) return;

      // Persist the in-progress sign-up so a fully-killed app can resume
      // this exact OTP session from the auth screen.
      await PendingSignupService.instance.save(PendingSignup(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phoneNumber: e164Phone,
        countryCode: phoneNumberField.selectedCountry.code,
        otpId: otpId,
      ));
      if (!mounted) return;

      Navigator.pushNamed(
        context,
        RouteNames.phoneVerificationPage,
        arguments: PhoneVerificationArguments(
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phoneNumber: e164Phone,
          country: phoneNumberField.selectedCountry,
          otpId: otpId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      QuickAlert.show(
        context: context,
        type: QuickAlertType.error,
        title: "Couldn't Send Code",
        text: _getErrorMessage(e),
        backgroundColor: FcAppColors.of(context).surface,
        headerBackgroundColor: FcAppColors.of(context).surface,
        titleColor: FcAppColors.of(context).textPrimary,
        textColor: FcAppColors.of(context).textSecondary,
      );
    } finally {
      if (mounted) {
        setState(() => _sendingOtp = false);
      }
    }
  }

  final GlobalKey<PhoneNumberFieldState> _phoneFieldKey =
      GlobalKey<PhoneNumberFieldState>();

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: SlideTransition(
            position: _slideAnimation,
            child: const CustomText(
                text: 'Complete Your Profile',
                textColor: Colors.white,
                fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: Colors.lightBlueAccent,
        ),
        backgroundColor: colors.surface,
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0.w),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                        height: 100.h,
                        child: Image.asset('assets/logo.png',
                            fit: BoxFit.contain)),
                    SizedBox(height: 16.h),
                    CustomText(
                        textAlign: TextAlign.center,
                        text: 'Almost There',
                        fontSize: 24.sp,
                        fontWeight: FontWeight.bold),
                    SizedBox(height: 8.h),
                    CustomText(
                        text: 'Just a few more details to get you started.',
                        textAlign: TextAlign.center,
                        fontSize: 16.sp),
                    SizedBox(height: 32.h),
                    CustomTextFormField(
                        controller: _firstNameController,
                        text: 'First Name',
                        validator: (v) => v!.trim().isEmpty
                            ? 'Please enter your first name'
                            : null),
                    SizedBox(height: 12.h),
                    CustomTextFormField(
                      controller: _lastNameController,
                      text: 'Last Name',
                      validator: (v) => null,
                    ),
                    SizedBox(height: 12.h),
                    PhoneNumberField(
                      key: _phoneFieldKey,
                      controller: _phoneController,
                    ),
                    SizedBox(height: 8.h),
                    CustomText(
                      text:
                          'A 6-digit verification code will be sent to your email.',
                      textAlign: TextAlign.center,
                      textColor: colors.textWeak,
                      fontSize: 13.sp,
                    ),
                    SizedBox(height: 24.h),
                    _sendingOtp
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Colors.lightBlueAccent))
                        : CustomButton(
                            onPressed: _sendOtp,
                            buttonColor: Colors.lightBlueAccent,
                            child: CustomText(
                                text: 'Send OTP',
                                textColor: Colors.white,
                                fontSize: 18.sp),
                          ),
                    SizedBox(height: 24.h),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
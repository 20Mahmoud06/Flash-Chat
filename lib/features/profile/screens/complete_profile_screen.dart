import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/country_codes.dart';
import 'package:flash_chat_app/features/auth/widgets/phone_number_field.dart';
import 'package:flash_chat_app/features/auth/models/phone_verification_arguments.dart';
import 'package:flash_chat_app/features/auth/services/phone_registry.dart';
import 'package:flash_chat_app/features/auth/services/pending_signup_service.dart';
import 'package:flash_chat_app/features/profile/cubit/profile_cubit.dart';
import 'package:flash_chat_app/services/otp/otp_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_button.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flash_chat_app/shared/widgets/custom_text_form_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  bool _prefilling = false;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  CountryCode? _initialCountry;

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

    _prefillFromStoredProfile();

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

  /// Fills any still-empty field from the profile already stored in the cloud.
  ///
  /// This screen is re-entered after the account document was already written
  /// — from the auth screen's "Continue Sign Up" resume button, from
  /// "Wrong number? Change it" on the verify screen, or on a reinstall. In all
  /// of those cases the user has already typed this information once, so
  /// making them retype it is both tedious and a real risk: a mistyped name or
  /// number silently overwrites the good one they saved earlier.
  ///
  /// Only EMPTY fields are touched, so nothing the user has begun typing is
  /// ever overwritten, and a failure here is non-fatal — an unreadable document
  /// just leaves the form blank, which is where it would have been anyway.
  Future<void> _prefillFromStoredProfile() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    setState(() => _prefilling = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .get();
      if (!mounted) return;
      final data = doc.exists ? doc.data() : null;
      if (data == null) return;

      final storedFirst = (data['firstName'] as String? ?? '').trim();
      final storedLast = (data['lastName'] as String? ?? '').trim();
      final storedPhone = (data['phoneNumber'] as String? ?? '').trim();

      var changed = false;
      if (_firstNameController.text.trim().isEmpty && storedFirst.isNotEmpty) {
        _firstNameController.text = storedFirst;
        changed = true;
      }
      if (_lastNameController.text.trim().isEmpty && storedLast.isNotEmpty) {
        _lastNameController.text = storedLast;
        changed = true;
      }
      if (_phoneController.text.trim().isEmpty && storedPhone.isNotEmpty) {
        // The field is fed the full international digits; PhoneNumberField
        // strips the country's own prefix again when building the E.164 value,
        // so the stored and re-sent numbers stay byte-identical.
        final digits = storedPhone.replaceAll(RegExp(r'\D'), '');
        if (digits.isNotEmpty) {
          _phoneController.text = digits;
          _initialCountry = CountryCodes.countryForPhone(storedPhone);
          changed = true;
        }
      }

      if (changed) setState(() {});
    } catch (e) {
      debugPrint('Could not prefill profile form: $e');
    } finally {
      if (mounted) setState(() => _prefilling = false);
    }
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
      //
      // This account's OWN number must be excluded: re-running the profile step
      // (the auth screen's "Continue Sign Up" resume, or "Wrong number? Change
      // it" after a prefill) legitimately re-sends to the number this account
      // already claims. Without the exclusion the resumed flow died on
      // "This phone number is already registered." before ever reaching the
      // verify screen.
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (await PhoneRegistry.instance
          .isPhoneInUse(e164Phone, excludeUid: currentUid)) {
        throw 'This phone number is already registered.';
      }
      if (!mounted) return;

      // Persist the profile BEFORE the code goes out.
      //
      // Without this the name and number existed only in the on-phone draft, so
      // killing the app on the verify screen lost everything the user typed,
      // and resuming on another device had nothing to prefill from. Saving
      // first also means a failed SMS costs nothing — the profile is safe and
      // the screen can simply be retried.
      await context.read<ProfileCubit>().completeUserProfile(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            phoneNumber: e164Phone,
            phoneVerified: false,
          );

      final otpId = await _otpService.sendOtp(phone: e164Phone);
      if (!mounted) return;

      // Advance the onboarding draft to the OTP step, so a fully-killed app
      // comes back to the auth screen with a "Verify Phone Number" button that
      // can still use this code. The uid ties the draft to this account so it
      // can never resume someone else's sign-up.
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        await PendingSignupService.instance.save(PendingSignup(
          uid: authUser.uid,
          step: PendingSignupStep.otp,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phoneNumber: e164Phone,
          countryCode: phoneNumberField.selectedCountry.code,
          otpId: otpId,
        ));
        if (!mounted) return;
      }

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
                      initialCountry: _initialCountry,
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
                    _sendingOtp || _prefilling
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Colors.lightBlueAccent))
                        : CustomButton(
                            // Held disabled until any prefill has landed, so
                            // nobody can send a code for a half-filled form
                            // in the moment before their saved number appears.
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

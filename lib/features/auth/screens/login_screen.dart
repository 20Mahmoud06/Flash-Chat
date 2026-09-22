import 'package:flash_chat_app/features/auth/cubit/auth_state.dart';
import 'package:flash_chat_app/features/home/screens/home_screen.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/features/profile/screens/complete_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:quickalert/quickalert.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../shared/widgets/custom_text_form_field.dart';
import '../cubit/auth_cubit.dart';
import '../widgets/google_signin_button.dart';
import '../../../core/utils/page_transition.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isGoogleLoading = false;
  bool _navigated = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _loginWithEmail() {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState!.validate()) {
      context.read<AuthCubit>().loginWithEmail(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );
    }
  }

  void _loginWithGoogle() {
    FocusScope.of(context).unfocus();
    setState(() => _isGoogleLoading = true);
    context.read<AuthCubit>().loginWithGoogle().whenComplete(() {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    });
  }

  void _goHome() {
    if (_navigated) return;
    _navigated = true;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: PageTransition.slideFromRight,
      ),
    );
  }

  /// Decides where a freshly-signed-in user lands. A completed profile (any
  /// non-empty name) goes Home immediately; an EMPTY name is NOT trusted on
  /// its own — the sign-in snapshot can race the profile write or read a
  /// stale cache shell, which used to bounce existing users into "Complete
  /// Profile" until they killed and reopened the app. So the profile is
  /// re-resolved against the server (same rule the cold-start/splash uses:
  /// an existing profile WITH a name OR a previously-known profile ⇒ Home;
  /// a missing or name-less shell document ⇒ Complete Profile).
  Future<void> _handleLoggedIn(UserModel user) async {
    if (user.firstName.isNotEmpty) {
      _goHome();
      return;
    }
    final resolved = await context.read<AuthCubit>().resolvePostSignIn(user.uid);
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (resolved != null) {
      _goHome();
    } else {
      // No completed profile and nothing known about it server-side: offer
      // the full sign-up resume (names, phone, OTP).
      if (!_navigated) {
        _navigated = true;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                CompleteProfileScreen(user: user),
            transitionsBuilder: PageTransition.slideFromRight,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) async {
        // Only react while this screen is the current route. Login stays
        // mounted below Sign Up / Reset Password (pushed with pushNamed),
        // and its listener would otherwise also fire for errors and
        // success states meant for those screens - e.g. a "Login Failed"
        // dialog stacked behind a "Sign Up Failed" dialog, or a duplicate
        // navigation when the sign-up succeeds.
        if (ModalRoute.of(context)?.isCurrent != true) return;
        if (state is AuthLoggedIn) {
          await _handleLoggedIn(state.user);
        } else if (state is AuthNeedsProfile) {
          // Signed in but the profile was never completed (closed the app
          // on the OTP verify or complete profile screen): resume the
          // sign-up on the complete-profile screen.
          if (!_navigated) {
            _navigated = true;
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const CompleteProfileScreen(),
                transitionsBuilder: PageTransition.slideFromRight,
              ),
            );
          }
        } else if (state is AuthError) {
          if (_isGoogleLoading) {
            setState(() => _isGoogleLoading = false);
          }
          QuickAlert.show(
            context: context,
            type: QuickAlertType.error,
            title: "Login Failed",
            text: state.message,
            backgroundColor: FcAppColors.of(context).surface,
            headerBackgroundColor: FcAppColors.of(context).surface,
            titleColor: FcAppColors.of(context).textPrimary,
            textColor: FcAppColors.of(context).textSecondary,
          );
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: colors.surface,
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0.w),
            child: Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Spacer(),
                            Hero(
                              tag: 'logo',
                              child: SizedBox(
                                height: 180.0.h,
                                child: Image.asset('assets/logo.png'),
                              ),
                            ),
                            SizedBox(height: 40.0.h),
                            CustomTextFormField(
                              controller: _emailController,
                              text: 'Email Address',
                              isEmail: true,
                              textInputAction: TextInputAction.next,
                              validator: validateEmail,
                            ),
                            SizedBox(height: 8.0.h),
                            CustomTextFormField(
                              controller: _passwordController,
                              text: 'Password',
                              isPassword: true,
                              textInputAction: TextInputAction.done,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Please enter your password';
                                } else if (v.length < 6) {
                                  return 'Password must be at least 6 characters long';
                                }
                                return null;
                              },
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  Navigator.pushNamed(
                                      context, RouteNames.resetPassword);
                                },
                                child: CustomText(
                                  text: 'Forgot Password?',
                                  textColor: Colors.lightBlueAccent,
                                  fontSize: 14.sp,
                                ),
                              ),
                            ),
                            SizedBox(height: 8.h),
                            BlocBuilder<AuthCubit, AuthState>(
                              builder: (context, state) {
                                final isEmailLoading =
                                    state is AuthLoading && !_isGoogleLoading;
                                return CustomButton(
                                  onPressed: isEmailLoading || _isGoogleLoading
                                      ? null
                                      : _loginWithEmail,
                                  buttonColor: Colors.lightBlueAccent,
                                  child: isEmailLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : CustomText(
                                          text: 'Log In',
                                          textColor: Colors.white,
                                          fontSize: 18.sp,
                                        ),
                                );
                              },
                            ),
                            SizedBox(height: 12.0.h),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(child: Divider(color: colors.divider)),
                                Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 8.0.w),
                                  child: CustomText(
                                      text: 'OR',
                                      textColor: colors.textWeak,
                                      fontSize: 16.sp),
                                ),
                                Expanded(child: Divider(color: colors.divider)),
                              ],
                            ),
                            SizedBox(height: 12.0.h),
                            GoogleSigninButton(
                              text: 'Login with Google',
                              isLoading: _isGoogleLoading,
                              onPressed:
                                  _isGoogleLoading ? null : _loginWithGoogle,
                            ),
                            const Spacer(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CustomText(
                                    text: "Don't have an account? ",
                                    fontSize: 16.sp),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pushNamed(
                                        context, RouteNames.signup);
                                  },
                                  child: CustomText(
                                    text: 'Sign Up',
                                    textColor: Colors.lightBlueAccent,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 24.h),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

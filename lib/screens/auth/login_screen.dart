import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/screens/home/home_screen.dart';
import 'package:flash_chat_app/screens/profile/complete_profile_screen.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:quickalert/quickalert.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/routes/route_names.dart';
import '../../cubits/auth_cubit/auth_cubit.dart';
import '../../cubits/auth_cubit/auth_state.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../widgets/google_signin_button.dart';
import '../../utils/page_transition.dart';

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

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) async {
        if (state is AuthLoggedIn) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(state.user.uid)
              .get();

          final profileData = userDoc.data();
          if (userDoc.exists &&
              profileData != null &&
              profileData['firstName'] != null &&
              profileData['firstName'].isNotEmpty) {
            Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
                  transitionsBuilder: PageTransition.slideFromRight,
                ));
          } else {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => CompleteProfileScreen(user: state.user),
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
          );
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          backgroundColor: Colors.white,
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
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Please enter your email';
                                }
                                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                    .hasMatch(v)) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
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
                                Expanded(
                                    child:
                                    Divider(color: Colors.grey.shade400)),
                                Padding(
                                  padding:
                                  EdgeInsets.symmetric(horizontal: 8.0.w),
                                  child: CustomText(
                                      text: 'OR',
                                      textColor: Colors.grey,
                                      fontSize: 16.sp),
                                ),
                                Expanded(
                                    child:
                                    Divider(color: Colors.grey.shade400)),
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
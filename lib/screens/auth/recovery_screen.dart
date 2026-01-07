import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:quickalert/quickalert.dart';
import '../../cubits/auth_cubit/auth_cubit.dart';
import '../../cubits/auth_cubit/auth_state.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_form_field.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();

  bool isGoogleLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _resetPassword() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthCubit>().resetPassword(_emailController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthLoading) {
        } else if (state is AuthPasswordResetSent) {
          QuickAlert.show(
            context: context,
            type: QuickAlertType.success,
            title: "Check Your Email",
            text: "A password reset link has been sent to your email address.",
            onConfirmBtnTap: () {
              Navigator.of(context).pop(); // Dismiss alert
              Navigator.of(context).pop(); // Go back to login
            },
          );
        } else if (state is AuthError) {
          QuickAlert.show(
            context: context,
            type: QuickAlertType.error,
            title: "Error",
            text: state.message,
          );
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
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
                              textInputAction: TextInputAction.done,
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
                            SizedBox(height: 24.0.h),
                            BlocBuilder<AuthCubit, AuthState>(
                              builder: (context, state) {
                                if (state is AuthLoading) {
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.lightBlueAccent,
                                    ),
                                  );
                                }
                                return CustomButton(
                                  onPressed: _resetPassword,
                                  buttonColor: Colors.lightBlueAccent,
                                  child: CustomText(
                                    text: 'Send Reset Link',
                                    textColor: Colors.white,
                                    fontSize: 18.sp,
                                  ),
                                );
                              },
                            ),
                            const Spacer(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CustomText(
                                    text: "Remember your password? ",
                                    fontSize: 16.sp),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                  },
                                  child: CustomText(
                                    text: 'Log In',
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
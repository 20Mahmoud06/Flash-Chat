import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/routes/route_names.dart';
import '../cubits/auth_cubit/auth_cubit.dart';
import '../cubits/auth_cubit/auth_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Ask the AuthCubit to check the user's status when the screen loads
    context.read<AuthCubit>().checkAuthStatus();
  }

  @override
  Widget build(BuildContext context) {
    // BlocListener waits for the state to change, then performs an action like navigating.
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthLoggedIn) {
          // User is logged in and profile is good -> go to home page
          Navigator.pushReplacementNamed(context, RouteNames.homePage);
        } else if (state is AuthNeedsProfile) {
          // User is logged in but needs profile -> go to complete profile page
          Navigator.pushReplacementNamed(
            context,
            RouteNames.completeProfilePage,
            arguments: state.user,
          );
        } else if (state is AuthLoggedOut) {
          // No user is logged in -> go to welcome screen
          Navigator.pushReplacementNamed(context, RouteNames.welcome);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: 'logo',
                child: Image.asset(
                  'assets/logo.png',
                  width: 150,
                  height: 150,
                ),
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(
                color: Colors.lightBlueAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
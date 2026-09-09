import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';

import '../core/routes/route_names.dart';
import '../core/utils/onboarding_permissions.dart';
import '../features/auth/cubit/auth_cubit.dart';
import '../features/auth/cubit/auth_state.dart';
import '../services/deep_link_service.dart';
import '../shared/widgets/permission_onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Never navigate twice (watchdog vs. real auth state).
  bool _resolved = false;

  /// Belt-and-suspenders: if checkAuthStatus can never resolve for any
  /// reason, land on the auth screen instead of leaving the splash forever
  /// (which looks like a crash after reopening the app).
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService().setNavReady();
    });
    _watchdog = Timer(const Duration(seconds: 10), _fallbackToWelcome);
    context.read<AuthCubit>().checkAuthStatus();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  void _fallbackToWelcome() {
    if (!mounted || _resolved) return;
    // State is unknown: clear stale deep links and offer the auth screen,
    // going through the same first-run onboarding path as _goTo.
    DeepLinkService().setLoggedOut();
    _goTo(RouteNames.welcome);
  }

  Future<void> _goTo(String route) async {
    if (!mounted || _resolved) return;
    _resolved = true;
    _watchdog?.cancel();
    // First launch ever → show the one-time permissions onboarding right after
    // the splash (before sign up / log in), then continue to the target.
    final showOnboarding = await OnboardingPermissions.instance.shouldShow();
    if (!mounted) return;
    if (showOnboarding) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PermissionOnboardingScreen(nextRoute: route),
        ),
      );
    } else {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthLoggedIn) {
          // Signed in with a completed profile: go to the home screen.
          DeepLinkService().setAuthReady();
          _goTo(RouteNames.homePage);
        } else if (state is AuthNeedsProfile) {
          // Signed in but the profile was never completed (e.g. the app was
          // closed on the "complete profile" or OTP verify screen): land on
          // the auth screen, which offers to resume exactly where the user
          // left off (Verify Phone Number / Continue Sign Up / Sign Out).
          DeepLinkService().setAuthReady();
          _goTo(RouteNames.welcome);
        } else if (state is AuthLoggedOut) {
          // Not signed in (or the session could not be restored): auth
          // screen with Sign In / Sign Up / Verify Phone options.
          DeepLinkService().setLoggedOut();
          _goTo(RouteNames.welcome);
        } else if (state is AuthError) {
          // Any auth failure must never leave the splash stuck: offer the
          // auth options again.
          DeepLinkService().setLoggedOut();
          _goTo(RouteNames.welcome);
        }
      },
      child: Scaffold(
        backgroundColor: colors.surface,
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
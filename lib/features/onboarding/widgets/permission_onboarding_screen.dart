import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/onboarding_permissions.dart';
import 'permission_all_done_view.dart';
import 'permission_denied_dialog.dart';
import 'permission_onboarding_bottom_bar.dart';
import 'permission_onboarding_header.dart';
import 'permission_onboarding_page_view.dart';
import 'permission_onboarding_progress.dart';
import 'permission_page.dart';

/// A one-time onboarding flow (single [PageView], not separate screens) that
/// asks for permissions PROGRESSIVELY — one at a time, and only for what is
/// actually needed on this device. Already-granted or non-applicable
/// permissions are skipped, so the user is never hit with a wall of prompts.
///
/// Every step is optional: "Skip" always lets the user continue; nothing here
/// blocks functionality.
class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key, this.nextRoute});

  /// Route to navigate to (with replacement) once onboarding finishes. When
  /// null the screen simply pops, e.g. when it was pushed on top of Home.
  final String? nextRoute;

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState
    extends State<PermissionOnboardingScreen> {
  final _service = OnboardingPermissions.instance;
  final _controller = PageController();

  final List<PermissionPage> _pages = [];
  int _current = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _buildPages();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Builds the step list from what this device actually needs, in order.
  Future<void> _buildPages() async {
    final pages = <PermissionPage>[];

    final notifGranted = await _service.notificationsGranted();
    if (!notifGranted) {
      pages.add(PermissionPage(
        title: 'Get message & call alerts',
        subtitle:
            'Be notified instantly when someone messages or calls you, even '
            'while the app is in the background.',
        icon: Icons.notifications_active_rounded,
        iconColor: AppColors.blueDeep,
        iconBackground: AppColors.skyTint,
        action: _enableNotifications,
      ));
    }

    final fullGranted = await _service.fullScreenIntentGranted();
    if (!fullGranted) {
      pages.add(PermissionPage(
        title: 'Incoming calls on your lock screen',
        subtitle:
            'Allow full-screen call notifications so an incoming call shows '
            'clearly on your lock screen. You can change this any time in '
            'Settings.',
        icon: Icons.fullscreen_rounded,
        iconColor: AppColors.tealDeep,
        iconBackground: AppColors.tealTint,
        action: _enableFullScreen,
      ));
    }

    if (!mounted) return;
    setState(() {
      _pages.addAll(pages);
      _loading = false;
    });
  }

  Future<void> _enableNotifications() async {
    final granted = await _service.requestFullNotificationPermission();
    if (!mounted) return;

    if (!granted) {
      // User denied — mark so we never re-prompt automatically, then show
      // an informational dialog.
      await _service.markNotificationsDenied();
      if (!mounted) return;
      await showPermissionDeniedDialog(context);
    }

    _nextStep();
  }

  Future<void> _enableFullScreen() async {
    // Opens the Android 14+ full-screen-notifications settings screen (no-op
    // elsewhere). Brief pause so the user can toggle before we advance.
    _service.requestFullScreenIntent();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _nextStep();
  }

  void _nextStep() {
    if (_current < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await _service.markShown();
    if (!mounted) return;
    final nextRoute = widget.nextRoute;
    if (nextRoute != null) {
      Navigator.of(context).pushReplacementNamed(nextRoute);
    } else {
      Navigator.of(context).pop();
    }
  }

  /// "Skip for now": treat a still-ungranted notification permission like a
  /// decline so the onboarding doesn't re-appear on every launch, but the user
  /// can still enable it any time from Profile > Notifications or Settings.
  Future<void> _skip() async {
    if (!await _service.notificationsGranted()) {
      await _service.markNotificationsDenied();
    }
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Scaffold(
      backgroundColor: colors.surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: _pages.isEmpty
                  ? PermissionAllDoneView(onDone: _finish)
                  : _buildFlow(),
            ),
    );
  }

  // ---------------- Main flow ----------------

  Widget _buildFlow() {
    final page = _pages[_current];
    final isLast = _current == _pages.length - 1;
    return Column(
      children: [
        // Modern gradient hero header with brand mark.
        const PermissionOnboardingHeader(),
        // Progress bar.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
          child: PermissionOnboardingProgress(
            total: _pages.length,
            current: _current,
          ),
        ),
        // Swipeable permission pages.
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) =>
                  PermissionOnboardingPageView(page: _pages[i]),
            ),
          ),
        ),
        // Bottom bar.
        PermissionOnboardingBottomBar(
          page: page,
          isLast: isLast,
          onSkip: _skip,
        ),
      ],
    );
  }
}

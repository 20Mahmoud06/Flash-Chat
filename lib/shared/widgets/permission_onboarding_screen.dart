import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/onboarding_permissions.dart';
import 'package:flash_chat_app/shared/widgets/custom_button.dart';

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

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen> {
  final _service = OnboardingPermissions.instance;
  final _controller = PageController();

  final List<_PermissionPage> _pages = [];
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
    final pages = <_PermissionPage>[];

    final notifGranted = await _service.notificationsGranted();
    if (!notifGranted) {
      pages.add(_PermissionPage(
        title: 'Get message & call alerts',
        subtitle:
            'Be notified instantly when someone messages or calls you, even '
            'while the app is in the background.',
        icon: Icons.notifications_active_rounded,
        iconColor: const Color(0xFF2E7CB4),
        iconBackground: const Color(0xFFE1F0FA),
        action: _enableNotifications,
      ));
    }

    final fullGranted = await _service.fullScreenIntentGranted();
    if (!fullGranted) {
      pages.add(_PermissionPage(
        title: 'Incoming calls on your lock screen',
        subtitle:
            'Allow full-screen call notifications so an incoming call shows '
            'clearly on your lock screen. You can change this any time in '
            'Settings.',
        icon: Icons.fullscreen_rounded,
        iconColor: const Color(0xFF00897B),
        iconBackground: const Color(0xFFE0F2F1),
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
      await _showNotificationDeniedDialog();
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

  Future<void> _showNotificationDeniedDialog() async {
    final colors = FcAppColors.of(context);
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72.w,
              height: 72.h,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_off_rounded,
                color: Colors.orange,
                size: 38.w,
              ),
            ),
            SizedBox(height: 18.h),
            Text(
              'You\'ll miss out!',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'Without notifications you won\'t know when someone messages '
              'or calls you. You can turn them on later from:\n\n'
              '  \u2022  Your phone\'s Settings > Flash Chat\n'
              '  \u2022  Profile > Notifications',
              textAlign: TextAlign.left,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14.sp,
                height: 1.5,
              ),
            ),
            SizedBox(height: 20.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                ),
                child: Text(
                  'Got it',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
              child: _pages.isEmpty ? _buildAllDone(colors) : _buildFlow(colors),
            ),
    );
  }

  // ---------------- Main flow ----------------

  Widget _buildFlow(FcAppColors colors) {
    final page = _pages[_current];
    final isLast = _current == _pages.length - 1;
    return Column(
      children: [
        // Modern gradient hero header with brand mark.
        _buildHeader(colors),
        // Progress bar.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
          child: _buildProgress(colors),
        ),
        // Swipeable permission pages.
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, i) => _buildPage(colors, _pages[i]),
                ),
              ),
            ],
          ),
        ),
        // Bottom bar.
        _buildBottomBar(colors, page, isLast),
      ],
    );
  }

  Widget _buildHeader(FcAppColors colors) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 28.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.lightBlueAccent,
            Color(0xFF4FB3E0),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28.r),
          bottomRight: Radius.circular(28.r),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand row: logo + wordmark (matches Welcome screen identity).
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14.r),
                child: Image.asset(
                  'assets/logo.png',
                  width: 44.w,
                  height: 44.h,
                  fit: BoxFit.cover,
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                'Flash Chat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: 22.h),
          FadeInDown(
            duration: const Duration(milliseconds: 450),
            child: Text(
              'Welcome!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(height: 6.h),
          FadeInDown(
            duration: const Duration(milliseconds: 450),
            delay: const Duration(milliseconds: 100),
            child: Text(
              'A couple of quick settings\nto get the best experience.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 14.sp,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(FcAppColors colors) {
    final total = _pages.length;
    return Row(
      children: List.generate(total, (i) {
        final active = i <= _current;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 6.h,
            margin: EdgeInsets.symmetric(horizontal: 3.w),
            decoration: BoxDecoration(
              color: active ? Colors.lightBlueAccent : colors.surfaceDim,
              borderRadius: BorderRadius.circular(3.r),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPage(FcAppColors colors, _PermissionPage page) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 28.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large icon in a soft tinted circle (matches avatar tint style).
          ZoomIn(
            duration: const Duration(milliseconds: 400),
            child: Container(
              width: 132.w,
              height: 132.h,
              decoration: BoxDecoration(
                color: page.iconBackground,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: page.iconColor.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(page.icon, color: page.iconColor, size: 62.w),
            ),
          ),
          SizedBox(height: 30.h),
          FadeInUp(
            duration: const Duration(milliseconds: 400),
            delay: const Duration(milliseconds: 120),
            child: Text(
              page.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 12.h),
          FadeInUp(
            duration: const Duration(milliseconds: 400),
            delay: const Duration(milliseconds: 200),
            child: Text(
              page.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14.sp,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(FcAppColors colors, _PermissionPage page, bool isLast) {
    return Container(
      padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 16.h),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Matches the app's CustomButton look (lightBlueAccent, white,
          // fully rounded).
          CustomButton(
            buttonColor: Colors.lightBlueAccent,
            onPressed: page.action,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isLast ? 'Done' : 'Allow',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 8.w),
                Icon(
                  isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20.w,
                ),
              ],
            ),
          ),
          SizedBox(height: 6.h),
          TextButton(
            onPressed: _skip,
            child: Text(
              'Skip for now',
              style: TextStyle(color: colors.textSecondary, fontSize: 14.sp),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- All permissions already granted ----------------

  Widget _buildAllDone(FcAppColors colors) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120.w,
              height: 120.h,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 64,
              ),
            ),
            SizedBox(height: 24.h),
            Text(
              'You\'re all set!',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 24.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Everything you need is already enabled.\nEnjoy Flash Chat!',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14.sp),
            ),
            SizedBox(height: 28.h),
            CustomButton(
              buttonColor: Colors.lightBlueAccent,
              onPressed: _finish,
              child: Text(
                'Let\'s go',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionPage {
  _PermissionPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.action,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback action;
}

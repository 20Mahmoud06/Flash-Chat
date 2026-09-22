import 'package:flash_chat_app/features/auth/services/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'app_call_listener.dart';
import 'core/routes/app_router.dart';
import 'core/routes/navigation_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/cubit/auth_cubit.dart';
import 'features/calls/bloc/call_bloc.dart';
import 'features/connectivity/cubit/connectivity_cubit.dart';
import 'features/profile/cubit/profile_cubit.dart';
import 'features/settings/cubit/theme_cubit.dart';
import 'features/onboarding/screens/splash_screen.dart';
import 'features/calls/widgets/call_in_progress_pill.dart';
import 'shared/widgets/connection_status_banner.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>(
              create: (_) => AuthCubit(AuthService()),
            ),
            BlocProvider<ProfileCubit>(
              create: (_) => ProfileCubit(),
            ),
            BlocProvider<ConnectivityCubit>(
              create: (_) => ConnectivityCubit(),
            ),
            BlocProvider<ThemeCubit>(
              create: (_) => ThemeCubit(),
            ),
            // App-wide call bloc: the Agora engine must survive the call
            // page being popped (minimized voice calls / video PiP).
            BlocProvider<CallBloc>(
              lazy: true,
              create: (_) => CallBloc.instance,
            ),
          ],
          child: AppCallListener(
            child: BlocBuilder<ThemeCubit, ThemeState>(
              builder: (context, themeState) {
                return MaterialApp(
                  navigatorKey: navigatorKey,
                  debugShowCheckedModeBanner: false,
                  title: 'Flash Chat',
                  theme: AppTheme.light,
                  darkTheme: AppTheme.dark,
                  themeMode: themeState.mode,
                  builder: _buildWithOfflineDetection,
                  onGenerateRoute: AppRouter.generateRoute,
                  navigatorObservers: [CallRouteObserver.instance],
                  home: const SplashScreen(),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildWithOfflineDetection(BuildContext context, Widget? child) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child!,
        const Align(
          alignment: Alignment.topCenter,
          child: ConnectionStatusBanner(),
        ),
        const CallInProgressPill(),
      ],
    );
  }
}
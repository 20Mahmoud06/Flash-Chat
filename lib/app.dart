import 'package:flash_chat_app/services/auth/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_offline/flutter_offline.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'app_call_listener.dart';
import 'core/routes/app_router.dart';
import 'core/routes/navigation_service.dart';
import 'features/auth/cubit/auth_cubit.dart';
import 'features/profile/cubit/profile_cubit.dart';
import 'screens/offline_screen.dart';
import 'screens/splash_screen.dart';

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
          ],
          child: AppCallListener(
            child: MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'Flash Chat',
              builder: _buildWithOfflineDetection,
              onGenerateRoute: AppRouter.generateRoute,
              home: const SplashScreen(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWithOfflineDetection(BuildContext context, Widget? child) {
    return OfflineBuilder(
      connectivityBuilder: (context, connectivity, offlineChild) {
        final bool connected = connectivity.any(
              (c) => c != ConnectivityResult.none,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            offlineChild,
            if (!connected) const OfflineScreen(),
          ],
        );
      },
      child: child!,
    );
  }
}
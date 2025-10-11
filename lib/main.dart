import 'package:firebase_core/firebase_core.dart';
import 'package:flash_chat_app/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_offline/flutter_offline.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'auth/auth.dart';
import 'core/routes/app_router.dart';
import 'core/routes/navigation_service.dart';
import 'firebase_options.dart';
import 'screens/offline_screen.dart';
import 'services/fcm_service.dart';
import 'cubits/auth_cubit/auth_cubit.dart';
import 'cubits/profile_cubit/profile_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FcmService().initializeFCM();
  runApp(const MyApp());
}

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
          child: MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            builder: (context, materialAppChild) {
              return OfflineBuilder(
                connectivityBuilder: (
                    BuildContext context,
                    List<ConnectivityResult> connectivity,
                    Widget child,
                    ) {
                  final bool connected =
                  connectivity.any((c) => c != ConnectivityResult.none);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      child,
                      if (!connected) const OfflineScreen(),
                    ],
                  );
                },
                child: materialAppChild!,
              );
            },
            onGenerateRoute: AppRouter.generateRoute,
            home: const SplashScreen(),
          ),
        );
      },
    );
  }
}
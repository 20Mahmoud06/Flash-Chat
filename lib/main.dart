import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flash_chat_app/screens/splash_screen.dart';
import 'package:flash_chat_app/utils/callkit_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_offline/flutter_offline.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app_call_listener.dart';
import 'auth/auth.dart';
import 'core/routes/app_router.dart';
import 'core/routes/navigation_service.dart';
import 'firebase_options.dart';
import 'screens/offline_screen.dart';
import 'services/fcm_service.dart';
import 'cubits/auth_cubit/auth_cubit.dart';
import 'cubits/profile_cubit/profile_cubit.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final data = message.data;
  if (data['type'] == 'call') {
    final callId = data['callId'];
    if (callId == null) return;

    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls.any((c) => c['id'] == callId)) return;

    final extra = <String, dynamic>{
      'type': 'call',
      'callId': callId,
      'isVideo': data['isVideo'] == 'true',
      'callerId': data['callerId'],
      'callerName': data['callerName'],
      'isGroup': data['isGroup'] == 'true',
      if (data.containsKey('groupId')) 'groupId': data['groupId'],
      if (data.containsKey('groupName')) 'groupName': data['groupName'],
      if (data.containsKey('receiverId')) 'receiverId': data['receiverId'],
    };
    await showIncomingCall(
      callerName: data['callerName'] ?? 'Unknown',
      isVideo: data['isVideo'] == 'true',
      callId: callId,
      extra: extra,
    );
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  unawaited(FcmService().initializeFCM());

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
          child: AppCallListener(
            child: MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              builder: (context, materialAppChild) {
                return OfflineBuilder(
                  connectivityBuilder: (context, connectivity, child) {
                    final bool connected = connectivity.any((c) => c != ConnectivityResult.none);
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
          ),
        );
      },
    );
  }
}
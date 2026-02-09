import 'package:flash_chat_app/core/routes/route_names.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/features/auth/screens/login_screen.dart';
import 'package:flash_chat_app/screens/offline_screen.dart';
import 'package:flash_chat_app/screens/splash_screen.dart';
import 'package:flash_chat_app/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/screens/contacts_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../models/call_arguments.dart';
import '../../features/auth/screens/recovery_screen.dart';
import '../../features/calls/screens/voice_call_page.dart';
import '../../features/chat/screens/home_screen.dart';
import '../../features/calls/screens/video_call_page.dart';
import '../../features/profile/screens/complete_profile_screen.dart';
import '../../features/groups/screens/edit_group_screen.dart';
import '../../features/profile/screens/sender_profile_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RouteNames.splashPage:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case RouteNames.welcome:
        return MaterialPageRoute(builder: (_) => const WelcomeScreen());
      case RouteNames.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case RouteNames.signup:
        return MaterialPageRoute(builder: (_) => const SignupScreen());
      case RouteNames.resetPassword:
        return MaterialPageRoute(builder: (_) => const ResetPasswordScreen());
      case RouteNames.profilePage:
        return MaterialPageRoute(builder: (_) => const ProfileScreen());
      case RouteNames.noInternetPage:
        return MaterialPageRoute(builder: (_) => const OfflineScreen());
      case RouteNames.homePage:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case RouteNames.completeProfilePage:
        return MaterialPageRoute(builder: (_) => CompleteProfileScreen(user: settings.arguments as UserModel?));
      case RouteNames.contactsPage:
        return MaterialPageRoute(builder: (_) => const ContactsScreen());

      case RouteNames.voiceCallPage:
        final args = settings.arguments as CallArguments;
        return MaterialPageRoute(
          builder: (_) => VoiceCallPage(
            isGroup: args.isGroup,
            group: args.group,
            contact: args.contact,
            callerId: args.callerId,
            callerName: args.callerName,
            callId: args.callId,
            groupName: args.groupName,
          ),
        );

      case RouteNames.videoCallPage:
        final args = settings.arguments as CallArguments;
        return MaterialPageRoute(
          builder: (_) => VideoCallPage(
            isGroup: args.isGroup,
            group: args.group,
            contact: args.contact,
            callerId: args.callerId,
            callerName: args.callerName,
            callId: args.callId,
            groupName: args.groupName,
          ),
        );

      case RouteNames.senderProfilePage:
        final user = settings.arguments as UserModel;
        return MaterialPageRoute(
            builder: (_) => SenderProfileScreen(user: user));

      case RouteNames.chatPage:
        final args = settings.arguments;
        if (args is UserModel) {
          return MaterialPageRoute(
            builder: (_) => ChatScreen(contact: args),
          );
        } else if (args is GroupModel) {
          return MaterialPageRoute(
            builder: (_) => ChatScreen(group: args),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
        );

      case RouteNames.editPagePage:
        final user = settings.arguments as UserModel;
        return MaterialPageRoute(
          builder: (_) => EditProfileScreen(user: user),
        );

      case RouteNames.editGroupPage:
        final group = settings.arguments as GroupModel;
        return MaterialPageRoute(
          builder: (_) => EditGroupScreen(group: group),
        );

      default:
        return MaterialPageRoute(builder: (_) => const WelcomeScreen());
    }
  }
}
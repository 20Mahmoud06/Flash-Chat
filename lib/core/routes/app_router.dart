import 'package:flash_chat_app/core/routes/route_names.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/phone_verification_arguments.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/features/auth/screens/login_screen.dart';
import 'package:flash_chat_app/features/auth/screens/phone_verification_screen.dart';
import 'package:flash_chat_app/screens/splash_screen.dart';
import 'package:flash_chat_app/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/chat/screens/group_chat_screen.dart';
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
import '../../features/profile/screens/blocked_users_screen.dart';

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
      case RouteNames.homePage:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case RouteNames.completeProfilePage:
        // The splash screen intentionally doesn't pass a UserModel here,
        // and old flows pass one from the auth state: accept both so a
        // cold start mid-signup can never crash on the cast.
        final completeProfileArgs = settings.arguments;
        final completeProfileUser =
            completeProfileArgs is UserModel ? completeProfileArgs : null;
        return MaterialPageRoute(
            builder: (_) => CompleteProfileScreen(user: completeProfileUser));
      case RouteNames.phoneVerificationPage:
        // Never crash on a missing/malformed argument (e.g. a cold-start
        // deep link targeting this screen): fall back to the auth screen.
        final verificationArgs = settings.arguments;
        if (verificationArgs is PhoneVerificationArguments) {
          return MaterialPageRoute(
              builder: (_) => PhoneVerificationScreen(arguments: verificationArgs));
        }
        return MaterialPageRoute(builder: (_) => const WelcomeScreen());

      case RouteNames.contactsPage:
        return MaterialPageRoute(builder: (_) => const ContactsScreen());

      case RouteNames.blockedUsersPage:
        return MaterialPageRoute(builder: (_) => const BlockedUsersScreen());

      case RouteNames.voiceCallPage:
        final callArgs = settings.arguments;
        if (callArgs is! CallArguments) {
          return MaterialPageRoute(builder: (_) => const WelcomeScreen());
        }
        return MaterialPageRoute(
          builder: (_) => VoiceCallPage(
            isGroup: callArgs.isGroup,
            group: callArgs.group,
            contact: callArgs.contact,
            callerId: callArgs.callerId,
            callerName: callArgs.callerName,
            callerAvatar: callArgs.callerAvatar,
            callId: callArgs.callId,
            groupName: callArgs.groupName,
          ),
        );

      case RouteNames.videoCallPage:
        final videoCallArgs = settings.arguments;
        if (videoCallArgs is! CallArguments) {
          return MaterialPageRoute(builder: (_) => const WelcomeScreen());
        }
        return MaterialPageRoute(
          builder: (_) => VideoCallPage(
            isGroup: videoCallArgs.isGroup,
            group: videoCallArgs.group,
            contact: videoCallArgs.contact,
            callerId: videoCallArgs.callerId,
            callerName: videoCallArgs.callerName,
            callerAvatar: videoCallArgs.callerAvatar,
            callId: videoCallArgs.callId,
            groupName: videoCallArgs.groupName,
            groupId: videoCallArgs.group?.id,
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
            builder: (_) => GroupChatScreen(group: args),
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
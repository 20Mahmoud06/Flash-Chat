import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/routes/route_names.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/screens/auth/login_screen.dart';
import 'package:flash_chat_app/screens/offline_screen.dart';
import 'package:flash_chat_app/screens/profile/profile_screen.dart';
import 'package:flash_chat_app/screens/splash_screen.dart';
import 'package:flash_chat_app/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import '../../screens/auth/recovery_screen.dart';
import '../../screens/auth/signup_screen.dart';
import '../../screens/home/chat_screen.dart';
import '../../screens/home/contacts_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/profile/complete_profile_screen.dart';
import '../../screens/profile/edit_profile_screen.dart';
import '../../screens/profile/sender_profile_screen.dart';


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

      case RouteNames.senderProfilePage:
        final user = settings.arguments as UserModel;
        return MaterialPageRoute(
            builder: (_) => SenderProfileScreen(user: user));

      case RouteNames.chatPage:
        final args = settings.arguments;
        if (args is UserModel) {
          final contact = args;
          final currentUser = FirebaseAuth.instance.currentUser!;
          final chatIdList = [currentUser.uid, contact.uid]..sort();
          final chatId = chatIdList.join('_');
          return MaterialPageRoute(
            builder: (_) => ChatScreen(contact: contact),
          );
        } else if (args is GroupModel) {
          final group = args;
          return MaterialPageRoute(
            builder: (_) => ChatScreen(group: group),
          );
        }
        return _errorRoute();

      case RouteNames.editProfilePage:
        final user = settings.arguments as UserModel;
        return MaterialPageRoute(
          builder: (_) => EditProfileScreen(user: user),
        );
      default:
        return MaterialPageRoute(builder: (_) => const WelcomeScreen());
    }
  }

  static Route<dynamic> _errorRoute() {
    return MaterialPageRoute(builder: (_) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(child: Text('Something went wrong with navigation')),
      );
    });
  }
}
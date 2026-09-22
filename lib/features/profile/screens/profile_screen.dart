import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:quickalert/quickalert.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transition.dart';
import '../../../shared/widgets/custom_text.dart';
import '../cubit/profile_cubit.dart';
import '../cubit/profile_state.dart';
import 'edit_profile_screen.dart';
import 'profile_reauth_flow.dart';
import 'profile_view.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return BlocProvider(
      create: (context) => ProfileCubit()..loadUserProfile(),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: colors.surface,
          appBar: AppBar(
            title: const CustomText(
              text: 'My Profile',
              textColor: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            centerTitle: true,
            backgroundColor: Colors.lightBlueAccent,
            elevation: 1,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              Builder(
                builder: (context) {
                  return IconButton(
                    onPressed: () async {
                      final state = context.read<ProfileCubit>().state;
                      if (state is ProfileLoaded) {
                        await Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    EditProfileScreen(user: state.user),
                            transitionsBuilder: PageTransition.slideFromRight,
                          ),
                        );
                        if (!context.mounted) return;
                        context.read<ProfileCubit>().loadUserProfile();
                      }
                    },
                    icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  );
                },
              ),
            ],
          ),
          body: BlocConsumer<ProfileCubit, ProfileState>(
            listener: (context, state) {
              if (state is ProfileLogoutSuccess) {
                Navigator.pushNamedAndRemoveUntil(
                    context, RouteNames.welcome, (route) => false);
              }
              if (state is ProfileReauthRequired) {
                handleReauth(context);
              }
              if (state is ProfileError) {
                if (!context.mounted) return;
                QuickAlert.show(
                  context: context,
                  type: QuickAlertType.error,
                  title: 'Error',
                  text: state.message,
                  backgroundColor: FcAppColors.of(context).surface,
                  headerBackgroundColor: FcAppColors.of(context).surface,
                  titleColor: FcAppColors.of(context).textPrimary,
                  textColor: FcAppColors.of(context).textSecondary,
                );
              }
              if (state is ProfileDeleteSuccess) {
                QuickAlert.show(
                  context: context,
                  type: QuickAlertType.success,
                  title: 'Deleted!',
                  text: 'Your account has been successfully deleted.',
                  barrierDismissible: false,
                  backgroundColor: FcAppColors.of(context).surface,
                  headerBackgroundColor: FcAppColors.of(context).surface,
                  titleColor: FcAppColors.of(context).textPrimary,
                  textColor: FcAppColors.of(context).textSecondary,
                  onConfirmBtnTap: () {
                    Navigator.pushNamedAndRemoveUntil(
                        context, RouteNames.welcome, (route) => false);
                  },
                );
              }
            },
            builder: (context, state) {
              if (state is ProfileError &&
                  context.read<ProfileCubit>().lastLoadedUser != null) {
                final user = context.read<ProfileCubit>().lastLoadedUser!;
                return ProfileView(user: user);
              }
              if (state is ProfileLoading && state is! ProfileLoaded) {
                return const Center(
                  child:
                      CircularProgressIndicator(color: Colors.lightBlueAccent),
                );
              }
              if (state is ProfileLoaded) {
                return ProfileView(user: state.user);
              }
              if (state is ProfileError) {
                return Center(
                  child: CustomText(
                    text: 'Could not load profile.\n${state.message}',
                  ),
                );
              }
              return const Center(
                child: CustomText(text: 'Welcome to your profile!'),
              );
            },
          ),
        ),
      ),
    );
  }
}

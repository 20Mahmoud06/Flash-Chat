import 'dart:async';
import 'package:flash_chat_app/features/connectivity/cubit/connectivity_cubit.dart';
import 'package:flash_chat_app/features/connectivity/cubit/connectivity_state.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Floating in-app notification shown at the top of the app.
///
/// - While offline: an amber pill with a spinner — "Connection lost.
///   Trying to reconnect…"
/// - Right after the connection is back: a green pill — "You're back online"
///   that disappears automatically after a couple of seconds.
class ConnectionStatusBanner extends StatefulWidget {
  const ConnectionStatusBanner({super.key});

  @override
  State<ConnectionStatusBanner> createState() => _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends State<ConnectionStatusBanner> {
  bool _wasOffline = false;
  bool _showReconnected = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ConnectivityCubit, ConnectivityStatus>(
      listenWhen: (prev, curr) => prev.offline != curr.offline,
      listener: (context, status) {
        if (status.offline) {
          _wasOffline = true;
          _timer?.cancel();
          if (mounted) {
            setState(() => _showReconnected = false);
          }
        } else if (_wasOffline) {
          _wasOffline = false;
          if (mounted) {
            setState(() => _showReconnected = true);
          }
          _timer?.cancel();
          _timer = Timer(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() => _showReconnected = false);
            }
          });
        } else {
          _wasOffline = false;
        }
      },
      child: BlocBuilder<ConnectivityCubit, ConnectivityStatus>(
        builder: (context, status) {
          if (!status.offline && !_showReconnected) {
            return const SizedBox.shrink();
          }

          final bool isOffline = status.offline;

          return Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.4),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: isOffline
                      ? _buildPill(
                          key: const ValueKey('offline'),
                          backgroundColor: Colors.red.shade50,
                          borderColor: Colors.red.shade200,
                          content: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12.w,
                                height: 12.w,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red.shade700,
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Flexible(
                                child: CustomText(
                                  text:
                                      'Connection lost — trying to reconnect...',
                                  textColor: Colors.red.shade800,
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w600,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildPill(
                          key: const ValueKey('reconnected'),
                          backgroundColor: Colors.green.shade100,
                          borderColor: Colors.green.shade300,
                          content: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_done_outlined,
                                color: Colors.green.shade700,
                                size: 18,
                              ),
                              SizedBox(width: 8.w),
                              Flexible(
                                child: CustomText(
                                  text: 'You\'re back online',
                                  textColor: Colors.green.shade800,
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPill({
    required Key key,
    required Color backgroundColor,
    required Color borderColor,
    required Widget content,
  }) {
    return Container(
      key: key,
      margin: EdgeInsets.only(top: 4.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
      constraints: BoxConstraints(maxWidth: 0.92.sw),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: content,
    );
  }
}

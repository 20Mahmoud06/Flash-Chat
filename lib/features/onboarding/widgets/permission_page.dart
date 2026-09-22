import 'package:flutter/material.dart';

/// A single optional step in the permission onboarding flow: a tinted icon,
/// a title, a subtitle and the action that requests the related permission.
class PermissionPage {
  PermissionPage({
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
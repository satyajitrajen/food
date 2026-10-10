import 'package:flutter/material.dart';

import '../core/media.dart';
import '../core/theme/app_theme.dart';

/// Staff photo, or their initial when there is no photo (or it fails to
/// load), never an empty circle.
class StaffAvatar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final String? apiBase;
  final double radius;

  const StaffAvatar({
    super.key,
    required this.name,
    this.avatarUrl = '',
    this.apiBase,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryGreenLight,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.85,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryGreen,
        ),
      ),
    );
    final url = resolveMediaUrl(avatarUrl, apiBase: apiBase ?? '');
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

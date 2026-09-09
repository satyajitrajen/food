import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/table_model.dart';
import '../models/kot_model.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color textColor;
  final Color bgColor;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.textColor,
    required this.bgColor,
    this.icon,
  });

  factory StatusBadge.forTable(TableStatus status) {
    switch (status) {
      case TableStatus.available:
        return const StatusBadge(
          label: 'Available',
          textColor: AppColors.vegGreen,
          bgColor: AppColors.vegGreenBg,
          icon: Icons.check_circle_outline,
        );
      case TableStatus.occupied:
        return const StatusBadge(
          label: 'Occupied',
          textColor: AppColors.primaryOrange,
          bgColor: AppColors.primaryOrangeLight,
          icon: Icons.people_outline,
        );
      case TableStatus.reserved:
        return const StatusBadge(
          label: 'Reserved',
          textColor: AppColors.infoBlue,
          bgColor: AppColors.infoBlueBg,
          icon: Icons.bookmark_border,
        );
      case TableStatus.billing:
        return const StatusBadge(
          label: 'Billing',
          textColor: AppColors.saffronAmber,
          bgColor: AppColors.saffronAmberBg,
          icon: Icons.receipt_long,
        );
      case TableStatus.cleaning:
        return const StatusBadge(
          label: 'Cleaning',
          textColor: AppColors.textMuted,
          bgColor: Color(0xFFF1F3F5),
          icon: Icons.cleaning_services_outlined,
        );
    }
  }

  factory StatusBadge.forKOT(KOTStatus status) {
    switch (status) {
      case KOTStatus.newTicket:
        return const StatusBadge(
          label: 'New',
          textColor: AppColors.infoBlue,
          bgColor: AppColors.infoBlueBg,
        );
      case KOTStatus.preparing:
        return const StatusBadge(
          label: 'Preparing',
          textColor: AppColors.saffronAmber,
          bgColor: AppColors.saffronAmberBg,
        );
      case KOTStatus.ready:
        return const StatusBadge(
          label: 'Ready',
          textColor: AppColors.vegGreen,
          bgColor: AppColors.vegGreenBg,
        );
      case KOTStatus.served:
        return const StatusBadge(
          label: 'Served',
          textColor: AppColors.textMuted,
          bgColor: Color(0xFFF1F3F5),
        );
      case KOTStatus.cancelled:
        return const StatusBadge(
          label: 'Cancelled',
          textColor: AppColors.nonVegRed,
          bgColor: AppColors.nonVegRedBg,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class VegMark extends StatelessWidget {
  final bool isVeg;
  final double size;

  const VegMark({super.key, required this.isVeg, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final color = isVeg ? AppColors.vegGreen : AppColors.nonVegRed;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

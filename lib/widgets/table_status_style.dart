import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/table_model.dart';

/// One visual language for table states: an icon + colour that reads at a
/// glance on a busy floor, with the word kept for tooltips/screen readers.
class TableStatusStyle {
  final IconData icon;
  final Color color;
  final Color background;
  final String label;

  const TableStatusStyle(this.icon, this.color, this.background, this.label);

  static TableStatusStyle of(TableStatus status) {
    switch (status) {
      case TableStatus.available:
        return const TableStatusStyle(
            Icons.check_circle_outline, AppColors.success, AppColors.successBg, 'Available');
      case TableStatus.occupied:
        return const TableStatusStyle(
            Icons.restaurant, AppColors.danger, AppColors.dangerBg, 'Occupied');
      case TableStatus.billing:
        return const TableStatusStyle(
            Icons.receipt_long, AppColors.warning, AppColors.warningBg, 'Billing');
      case TableStatus.reserved:
        return const TableStatusStyle(
            Icons.event_available, AppColors.infoBlue, AppColors.infoBlueBg, 'Reserved');
      case TableStatus.cleaning:
        return const TableStatusStyle(
            Icons.cleaning_services_outlined, AppColors.textMuted, AppColors.creamSubtle, 'Cleaning');
    }
  }

  /// Maps the provider's filter labels ('Available', ...) to a status.
  static TableStatus? fromLabel(String label) {
    for (final s in TableStatus.values) {
      if (of(s).label == label) return s;
    }
    return null;
  }
}

/// Round status icon with the status name as tooltip and semantics label.
class TableStatusIcon extends StatelessWidget {
  final TableStatus status;
  final double size;

  const TableStatusIcon({super.key, required this.status, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final style = TableStatusStyle.of(status);
    return Tooltip(
      message: style.label,
      child: Semantics(
        label: style.label,
        child: Container(
          padding: EdgeInsets.all(size * 0.3),
          decoration: BoxDecoration(color: style.background, shape: BoxShape.circle),
          child: Icon(style.icon, size: size, color: style.color),
        ),
      ),
    );
  }
}

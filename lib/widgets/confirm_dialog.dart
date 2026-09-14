import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Shared strict confirmation dialog. Returns true only when the user taps
/// the confirm button. Used for every destructive / money-moving / irreversible
/// action (strict mode — no Undo-only shortcuts).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDanger = true,
  IconData icon = Icons.warning_amber_rounded,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDanger ? AppColors.nonVegRedBg : AppColors.infoBlueBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isDanger ? AppColors.nonVegRed : AppColors.infoBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Text(message, style: const TextStyle(fontSize: 13)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isDanger ? AppColors.nonVegRed : AppColors.primaryGreen,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            confirmLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  return result == true;
}

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class PrinterErrorDialog extends StatelessWidget {
  final String printerName;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  const PrinterErrorDialog({
    super.key,
    this.printerName = 'Kitchen Thermal Printer (TVS RP3200)',
    required this.onRetry,
    required this.onContinue,
  });

  static void show(BuildContext context, {String? printerName, VoidCallback? onRetry, VoidCallback? onContinue}) {
    showDialog(
      context: context,
      builder: (ctx) => PrinterErrorDialog(
        printerName: printerName ?? 'Kitchen Thermal Printer (TVS RP3200)',
        onRetry: onRetry ?? () => Navigator.of(ctx).pop(),
        onContinue: onContinue ?? () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SizedBox(
          width: 500,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: AppColors.nonVegRedBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.print_disabled_outlined, color: AppColors.nonVegRed, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Printer Offline / Paper Jam',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Unable to communicate with $printerName. Check cables, paper roll, or network connection.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onContinue();
                      },
                      child: const Text('Skip Print'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onRetry();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry Print'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

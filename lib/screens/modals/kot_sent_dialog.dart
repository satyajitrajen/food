import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/kot_model.dart';

class KOTSentDialog extends StatelessWidget {
  final KitchenOrderTicket kot;
  final VoidCallback onAddMoreItems;
  final VoidCallback onViewOrder;
  final VoidCallback onGoToTables;

  const KOTSentDialog({
    super.key,
    required this.kot,
    required this.onAddMoreItems,
    required this.onViewOrder,
    required this.onGoToTables,
  });

  static void show(
    BuildContext context, {
    required KitchenOrderTicket kot,
    required VoidCallback onAddMoreItems,
    required VoidCallback onViewOrder,
    required VoidCallback onGoToTables,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => KOTSentDialog(
        kot: kot,
        onAddMoreItems: onAddMoreItems,
        onViewOrder: onViewOrder,
        onGoToTables: onGoToTables,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SizedBox(
          width: 460,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.vegGreenBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppColors.vegGreen, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'KOT Sent to Kitchen!',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
              const SizedBox(height: 6),
              Text(
                '${kot.kotNumber} · Table ${kot.tableNumber ?? "Counter"}',
                style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '${kot.totalQuantity} items dispatched to kitchen station.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 24),
              // Action Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onAddMoreItems();
                  },
                  child: const Text('Add More Items'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onViewOrder();
                  },
                  child: const Text('View Order Status'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onGoToTables();
                },
                child: const Text('Go to Floor Tables', style: TextStyle(color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

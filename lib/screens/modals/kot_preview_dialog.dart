import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/order_model.dart';
import '../../widgets/custom_badge.dart';

class KOTPreviewDialog extends StatelessWidget {
  final VoidCallback onSendKOT;

  const KOTPreviewDialog({super.key, required this.onSendKOT});

  static void show(BuildContext context, {required VoidCallback onSendKOT}) {
    showDialog(
      context: context,
      builder: (ctx) => KOTPreviewDialog(onSendKOT: onSendKOT),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final activeOrder = provider.activeOrder;

    if (activeOrder == null) return const SizedBox.shrink();

    final unsentItems = activeOrder.items.where((i) => !i.isKOTSent && !i.isCancelled).toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          width: 560,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryOrangeLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.receipt_outlined, color: AppColors.primaryOrange, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'KOT Ticket Preview',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          Text(
                            'Table: ${activeOrder.tableNumber ?? "Counter"} · Waiter: ${activeOrder.waiterName ?? "Staff"}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.creamSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ITEMS TO DISPATCH TO KITCHEN:',
                      style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w700, fontSize: 11),
                    ),
                    const Divider(color: AppColors.borderLight, height: 16),
                    for (OrderItem item in unsentItems) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.quantity} × ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: AppColors.primaryOrange,
                              ),
                            ),
                            VegMark(isVeg: item.menuItem.isVeg, size: 12),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                  if (item.selectedModifiers.isNotEmpty)
                                    Text(
                                      '+ ${item.selectedModifiers.map((m) => m.name).join(", ")}',
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                    ),
                                  if (item.itemNote != null)
                                    Text(
                                      'Note: "${item.itemNote}"',
                                      style: const TextStyle(color: AppColors.primaryOrange, fontSize: 11, fontStyle: FontStyle.italic),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (activeOrder.orderNote != null && activeOrder.orderNote!.isNotEmpty) ...[
                      const Divider(color: AppColors.borderLight, height: 16),
                      Text(
                        'General Note: ${activeOrder.orderNote}',
                        style: const TextStyle(
                          color: AppColors.saffronAmber,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back to Cart'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onSendKOT();
                      },
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Send to Kitchen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
}
}

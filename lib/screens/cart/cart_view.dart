import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/app_nav.dart';
import '../../widgets/custom_badge.dart';
import '../modals/kot_preview_dialog.dart';
import '../modals/kot_sent_dialog.dart';
import '../modals/manager_pin_dialog.dart';
import '../billing/bill_preview_screen.dart';

class CartViewScreen extends StatelessWidget {
  const CartViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final activeOrder = provider.activeOrder;

    if (activeOrder == null || activeOrder.items.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.creamBg,
        appBar: AppBar(
          title: const Text('Current Order', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shopping_basket_outlined, size: 54, color: AppColors.textLight),
                const SizedBox(height: 12),
                const Text('Your order cart is empty', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Add Dishes from Menu'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tableName = activeOrder.tableNumber ?? provider.selectedTable?.tableNumber ?? 'Counter';
    final hasUnsentItems = activeOrder.items.any((i) => !i.isKOTSent && !i.isCancelled);

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Table $tableName', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(
              '${activeOrder.orderNumber} · Waiter: ${activeOrder.waiterName ?? provider.currentStaff?.name ?? "Staff"}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'Order Notes',
            onPressed: () {
              final noteCtrl = TextEditingController(text: activeOrder.orderNote ?? '');
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Order-Level Note', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  content: SizedBox(
                    width: 500,
                    child: TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(hintText: 'e.g. Priority order, less spicy, anniversary table...'),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                    ElevatedButton(
                      onPressed: () {
                        provider.setOrderNote(noteCtrl.text.trim());
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Save Note'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Order Items List (cancelled items excluded entirely)
          Expanded(
            child: Builder(builder: (context) {
              final visibleItems =
                  activeOrder.items.where((i) => !i.isCancelled).toList();
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: visibleItems.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = visibleItems[index];

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VegMark(isVeg: item.menuItem.isVeg, size: 14),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                  ),
                                ),
                                Text(
                                  '₹${item.totalPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '₹${item.unitPrice.toStringAsFixed(0)} each',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                            if (item.selectedModifiers.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '+ ${item.selectedModifiers.map((m) => m.name).join(", ")}',
                                style: const TextStyle(color: AppColors.primaryOrange, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                            if (item.itemNote != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Note: "${item.itemNote}"',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
                              ),
                            ],
                            const SizedBox(height: 8),
                            // Quantity bar & KOT tag
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (item.isKOTSent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.vegGreenBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.check, size: 12, color: AppColors.vegGreen),
                                        SizedBox(width: 4),
                                        Text(
                                          'KOT Sent',
                                          style: TextStyle(color: AppColors.vegGreen, fontWeight: FontWeight.w700, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.saffronAmberBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'New Unsent',
                                      style: TextStyle(color: AppColors.saffronAmber, fontWeight: FontWeight.w700, fontSize: 11),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      onPressed: () async {
                                        // FR-A3: removing a KOT-sent line needs
                                        // manager authorization (server-gated too).
                                        String? managerPin;
                                        if (item.isKOTSent && item.quantity <= 1) {
                                          managerPin = await ManagerPinDialog.show(
                                            context,
                                            title: 'Manager Approval Required',
                                            description: 'Removing an item already sent to the kitchen requires Manager PIN.',
                                          );
                                          if (managerPin == null) return;
                                        }
                                        provider.decrementItem(item, managerPin: managerPin);
                                      },
                                    ),
                                    Text(
                                      '${item.quantity}',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.primaryOrange),
                                      onPressed: () => provider.incrementItem(item),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textLight),
                                      onPressed: () async {
                                        String? managerPin;
                                        if (item.isKOTSent) {
                                          managerPin = await ManagerPinDialog.show(
                                            context,
                                            title: 'Manager Approval Required',
                                            description: 'Removing an item already sent to the kitchen requires Manager PIN.',
                                          );
                                          if (managerPin == null) return;
                                        }
                                        provider.removeItem(item, managerPin: managerPin);
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  );
                },
              );
            }),
          ),

          // Bottom Summary & Actions
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Items Subtotal', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                      Text(
                        '₹${activeOrder.subtotal.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('+ Add Items'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (hasUnsentItems)
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                            onPressed: () {
                              KOTPreviewDialog.show(
                                context,
                                onSendKOT: () {
                                  final kot = provider.sendKOT();
                                  if (kot != null) {
                                    KOTSentDialog.show(
                                      context,
                                      kot: kot,
                                      onAddMoreItems: () => Navigator.of(context).pop(),
                                      onViewOrder: () {},
                                      onGoToTables: () {
                                        Navigator.of(context).pop();
                                        provider.goToDest(AppDest.tables); // Tables tab
                                      },
                                    );
                                  }
                                },
                              );
                            },
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: const Text('Send KOT'),
                          ),
                        )
                      else
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.vegGreen),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const BillPreviewScreen()),
                              );
                            },
                            icon: const Icon(Icons.receipt_long, size: 16),
                            label: const Text('Checkout Bill'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

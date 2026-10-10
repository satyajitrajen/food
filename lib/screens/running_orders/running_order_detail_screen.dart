import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/order_model.dart';
import '../../widgets/custom_badge.dart';
import '../modals/move_table_dialog.dart';
import '../modals/merge_tables_dialog.dart';
import '../modals/cancel_item_dialog.dart';
import '../modals/manager_pin_dialog.dart';
import '../payment/payment_screen.dart';
import '../pos_menu/pos_menu_screen.dart';
import '../../widgets/system_insets.dart';
import '../../core/format.dart';

class RunningOrderDetailScreen extends StatelessWidget {
  final RestaurantOrder order;

  const RunningOrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    // Find current instance in provider
    final currentOrder = provider.orders.firstWhere((o) => o.id == order.id, orElse: () => order);
    // Only bind a table for dine-in orders; takeaway/delivery have none.
    final table = currentOrder.tableId == null
        ? null
        : provider.tables.where((t) => t.id == currentOrder.tableId).firstOrNull;
    final isClosed = currentOrder.isClosed;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: Text('${currentOrder.orderNumber} Details', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!isClosed && table != null) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outline),
              tooltip: 'Move Table',
              onPressed: () => MoveTableDialog.show(context, table),
            ),
            if (provider.canManage)
              IconButton(
                icon: const Icon(Icons.call_merge),
                tooltip: 'Merge Tables',
                onPressed: () => MergeTablesDialog.show(context, table),
              ),
          ],
          if (!isClosed && currentOrder.paymentSplits.isEmpty)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (_) => _cancelOrder(context, provider, currentOrder),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'cancel',
                  child: ListTile(
                    leading: Icon(Icons.block, color: AppColors.danger),
                    title: Text('Cancel order'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Order Header Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              currentOrder.tableNumber != null ? 'Table ${currentOrder.tableNumber}' : currentOrder.orderTypeLabel,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (table != null) ...[
                            const SizedBox(width: 8),
                            StatusBadge.forTable(table.status),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Waiter: ${currentOrder.waiterName ?? provider.currentStaff?.name ?? "Staff"} · ${plural(currentOrder.guestCount, 'Guest')}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((currentOrder.customerName ?? '').isNotEmpty ||
                          (currentOrder.customerPhone ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                [
                                  if ((currentOrder.customerName ?? '').isNotEmpty) currentOrder.customerName!,
                                  if ((currentOrder.customerPhone ?? '').isNotEmpty) currentOrder.customerPhone!,
                                ].join(' · '),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatInr(currentOrder.grandTotal),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.primaryGreen),
                    ),
                    Text(
                      plural(currentOrder.totalItemCount, 'item'),
                      style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),

          // Items List with Void / Cancel Option
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: currentOrder.items.length,
              itemBuilder: (context, index) {
                final item = currentOrder.items[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: item.isCancelled ? AppColors.nonVegRed.withValues(alpha: 0.3) : AppColors.borderLight,
                    ),
                  ),
                  child: Row(
                    children: [
                      VegMark(isVeg: item.menuItem.isVeg, size: 14),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.quantity} × ${item.displayName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      decoration: item.isCancelled ? TextDecoration.lineThrough : null,
                                      color: item.isCancelled ? AppColors.textLight : AppColors.textDark,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatInr(item.totalPrice),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    decoration: item.isCancelled ? TextDecoration.lineThrough : null,
                                    color: item.isCancelled ? AppColors.textLight : AppColors.textDark,
                                  ),
                                ),
                              ],
                            ),
                            if (item.selectedModifiers.isNotEmpty)
                              Text(
                                '+ ${item.selectedModifiers.map((m) => m.name).join(", ")}',
                                style: const TextStyle(color: AppColors.primaryGreen, fontSize: 11),
                              ),
                            if (item.isCancelled)
                              Text(
                                'VOIDED: "${item.cancelReason}"',
                                style: const TextStyle(color: AppColors.nonVegRed, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ),
                      if (!item.isCancelled && !isClosed)
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.nonVegRed),
                          tooltip: 'Cancel / Void Item',
                          onPressed: () {
                            CancelItemDialog.show(
                              context,
                              item: item,
                              onConfirmCancel: (reason, managerPin) {
                                provider.cancelItemFromOrder(
                                  orderId: currentOrder.id,
                                  itemId: item.id,
                                  reason: reason,
                                  managerPin: managerPin,
                                );
                              },
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bottom Primary Bar: Add Item vs Checkout (explicit bottom inset).
          Container(
            padding: BottomInsets.barAll(context, horizontal: 16, vertical: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: isClosed
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            currentOrder.status == OrderStatus.cancelled
                                ? 'Order cancelled / refunded'
                                : 'Paid · ${currentOrder.invoiceNumber ?? currentOrder.orderNumber}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              provider.openRunningOrder(currentOrder);
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const PosMenuScreen()),
                              );
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add items'),
                          ),
                        ),
                        if (provider.canTakePayment) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.vegGreen),
                              onPressed: () {
                                provider.openRunningOrder(currentOrder);
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const PaymentScreen()),
                                );
                              },
                              icon: const Icon(Icons.receipt, size: 18),
                              label: const Text('Checkout'),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Voids an unpaid order on the server (frees its table, cancels its
  /// KOTs). Once the kitchen has a KOT, a non-manager needs a manager PIN.
  Future<void> _cancelOrder(BuildContext context, PosProvider provider, RestaurantOrder order) async {
    const reasons = ['Customer left', 'Wrong order', 'Duplicate order', 'Other'];
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Cancel ${order.orderNumber}?'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('The bill is voided and its table is freed. Why?',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          for (final r in reasons)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(r, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    String? pin;
    final sentToKitchen = provider.kots.any((k) => k.orderId == order.id);
    if (sentToKitchen && !provider.canManage) {
      pin = await ManagerPinDialog.show(
        context,
        title: 'Approve cancel',
        description: 'The kitchen already has this order. A manager must approve cancelling it.',
      );
      if (pin == null || !context.mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await provider.cancelOrder(order.id, reason: reason, managerPin: pin);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text('Not cancelled: $error'), backgroundColor: AppColors.danger));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text('${order.orderNumber} cancelled'),
      backgroundColor: AppColors.success,
    ));
    navigator.maybePop();
  }
}

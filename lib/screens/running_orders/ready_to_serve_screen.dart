import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/kot_model.dart';
import '../../widgets/custom_badge.dart';
import '../../widgets/confirm_dialog.dart';

/// Waiter-facing "ready to serve" queue. Lists only the signed-in waiter's own
/// cooked tickets (never another waiter's); marking one served closes the
/// kitchen ticket for that order. Manager/cashier/admin open the same queue but
/// see the whole outlet so they can cover any table.
class ReadyToServeScreen extends StatelessWidget {
  const ReadyToServeScreen({super.key});

  Future<void> _markServed(BuildContext context, PosProvider provider, KitchenOrderTicket kot) async {
    // Capture the messenger before awaiting: the card leaves this list the
    // moment the ticket is served, taking its build context with it.
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showConfirmDialog(
      context,
      title: 'Mark served?',
      message: 'Mark ${kot.kotNumber} as Served? This closes the kitchen ticket.',
      confirmLabel: 'Mark Served',
      isDanger: false,
    );
    if (!ok || !context.mounted) return;
    provider.updateKOTStatus(kot.id, KOTStatus.served);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('${kot.kotNumber} marked Served', style: const TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.vegGreen,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final tickets = provider.readyToServe;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ready to Serve', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(
              tickets.length == 1 ? '1 order waiting' : '${tickets.length} orders waiting',
              style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: tickets.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.room_service_outlined, size: 54, color: AppColors.textLight),
                      SizedBox(height: 12),
                      Text(
                        'Nothing ready to serve',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Orders appear here the moment the kitchen marks them ready.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: tickets.length,
                itemBuilder: (context, index) {
                  final kot = tickets[index];
                  final timeStr = DateFormat('hh:mm a').format(kot.createdAt);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.vegGreen.withValues(alpha: 0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        kot.kotNumber,
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textDark),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryGreenLight,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          kot.tableNumber != null ? 'Table ${kot.tableNumber}' : kot.orderType.name.toUpperCase(),
                                          style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w800, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              StatusBadge.forKOT(kot.status),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ready at $timeStr · Waiter: ${kot.waiterName} · ${kot.totalQuantity} items',
                            style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Divider(height: 20, color: AppColors.borderLight),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: kot.items.map((item) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item.quantity} × ',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primaryGreen),
                                    ),
                                    VegMark(isVeg: item.menuItem.isVeg, size: 12),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        item.displayName,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          if (kot.specialInstructions != null && kot.specialInstructions!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.saffronAmberBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Ticket Note: ${kot.specialInstructions}',
                                style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.vegGreen),
                              onPressed: () => _markServed(context, provider, kot),
                              icon: const Icon(Icons.room_service, size: 18),
                              label: const Text('Mark Served'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

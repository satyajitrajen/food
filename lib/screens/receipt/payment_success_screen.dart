import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/share/bill_pdf.dart';
import '../../core/share/whatsapp_bill.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/bill_breakdown.dart';
import '../../models/order_model.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/dialog_controller_scope.dart';
import '../shell/main_adaptive_shell.dart';

class PaymentSuccessScreen extends StatelessWidget {
  final RestaurantOrder order;

  const PaymentSuccessScreen({super.key, required this.order});

  /// Sends the bill text to the customer's WhatsApp (wa.me deep link). When no
  /// phone was captured at the table, prompts for one first.
  Future<void> _shareOnWhatsApp(BuildContext context, RestaurantOrder order) async {
    final provider = context.read<PosProvider>();
    var phone = (order.customerPhone ?? '').trim();
    if (phone.isEmpty) {
      phone = (await _askPhone(context, order)) ?? '';
      if (!context.mounted) return;
    }
    final normalized = normalizeWaNumber(phone);
    if (normalized == null) {
      if (!context.mounted) return;
      showShareResult(context, false);
      return;
    }
    final ok = await shareBillOnWhatsApp(
      order: order,
      settings: provider.settings,
      outlet: provider.currentOutlet,
      phone: phone,
    );
    if (!context.mounted) return;
    showShareResult(context, ok);
  }

  Future<String?> _askPhone(BuildContext context, RestaurantOrder order) async {
    final c = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => DialogControllerScope(
        controllers: [c],
        builder: (ctx, _) => AlertDialog(
          title: const Text('Send Bill on WhatsApp'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customer mobile for ${order.customerName ?? 'this order'}?',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: c,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.phone_outlined, size: 18),
                    hintText: '10-digit mobile number',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    return phone;
  }

  /// Prints the bill on the configured thermal printer (respects reprint
  /// settings). Falls back to a message when no printer is reachable.
  Future<void> _printBill(BuildContext context, RestaurantOrder order) async {
    final provider = context.read<PosProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (!provider.settings.allowReprint) {
      messenger.showSnackBar(const SnackBar(content: Text('Reprint is disabled in Settings')));
      return;
    }
    final ok = await provider.reprintReceipt(order);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Bill sent to the printer'
          : (provider.printerError ?? 'Printer not reachable. Check Settings → Printers.')),
      backgroundColor: ok ? AppColors.vegGreen : AppColors.nonVegRed,
    ));
  }

  /// Shares a generated PDF bill through the OS share sheet.
  Future<void> _sharePdf(BuildContext context, RestaurantOrder order) async {
    final provider = context.read<PosProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final message = await BillShare.sharePdfBill(order, provider.settings);
    messenger.showSnackBar(SnackBar(
      content: Text(message ?? 'PDF bill ready to share'),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    // Follow the order to its server version (real invoice number) once the
    // payment is acknowledged.
    final order = provider.orderById(this.order.id) ?? this.order;
    final settings = provider.settings;
    final paidDate = order.paidAt ?? order.createdAt;
    final pending = order.invoiceNumber == null;
    final name = settings.restaurantName.isEmpty ? provider.currentOutlet.name : settings.restaurantName;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.successBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    order.paymentMethod == 'Credit' ? 'Billed to customer account' : 'Payment received',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatInr(order.grandTotal)} · ${_paymentSummary(order)}',
                    style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.creamCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Text(
                          name.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
                        ),
                        if (settings.address.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            settings.address,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                        if (settings.gstin.isNotEmpty || settings.fssai.isNotEmpty)
                          Text(
                            [
                              if (settings.gstin.isNotEmpty) 'GSTIN: ${settings.gstin}',
                              if (settings.fssai.isNotEmpty) 'FSSAI: ${settings.fssai}',
                            ].join(' · '),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textLight, fontSize: 10),
                          ),
                        const Divider(height: 20, thickness: 1, color: AppColors.borderMedium),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                pending ? 'Invoice: pending sync' : 'Invoice: ${order.invoiceNumber}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: pending ? AppColors.warning : AppColors.textDark,
                                ),
                              ),
                            ),
                            Text(formatDateTime(paidDate),
                                style: const TextStyle(color: AppColors.textLight, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                order.tableNumber != null
                                    ? 'Table ${order.tableNumber} · ${order.orderNumber}'
                                    : '${order.orderTypeLabel} · ${order.orderNumber}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            ),
                            if (order.waiterName != null)
                              Text(order.waiterName!,
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          ],
                        ),
                        const Divider(height: 20, thickness: 1, color: AppColors.borderMedium),
                        for (final item in order.activeItems)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.quantity} × ${item.displayName}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(formatInr(item.totalPrice),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        const Divider(height: 20, thickness: 1, color: AppColors.borderMedium),
                        BillBreakdown(order: order, showPayment: true),
                        const Divider(height: 24, thickness: 1, color: AppColors.borderLight),
                        const Text(
                          'Thank you for visiting!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textLight, fontSize: 11),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Actions: Print, WhatsApp, PDF, New Order
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _printBill(context, order),
                          icon: const Icon(Icons.print, size: 18),
                          label: const Text('Print Bill'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _shareOnWhatsApp(context, order),
                          icon: const Icon(Icons.chat, size: 18),
                          label: const Text('WhatsApp'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _sharePdf(context, order),
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('Share PDF Bill'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const MainAdaptiveShell()),
                          (route) => false,
                        );
                      },
                      child: const Text('Start Next Order →', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
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

String _paymentSummary(RestaurantOrder order) {
  if (order.paymentSplits.length > 1) {
    return 'Split (${order.paymentSplits.map((l) => l.method).join(' + ')})';
  }
  return order.paymentMethod ?? 'Cash';
}

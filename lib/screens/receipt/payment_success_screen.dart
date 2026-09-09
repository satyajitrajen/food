import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/share/bill_pdf.dart';
import '../../core/share/whatsapp_bill.dart';
import '../../core/theme/app_theme.dart';
import '../../models/order_model.dart';
import '../../providers/pos_provider.dart';
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
      builder: (ctx) => AlertDialog(
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
    );
    c.dispose();
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
    final paidDate = order.paidAt ?? DateTime.now();
    final dateFormatted = DateFormat('dd MMM yyyy, hh:mm a').format(paidDate);

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
                  // Success Tick Animation Header
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.vegGreenBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: AppColors.vegGreen, size: 48),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Payment Successful!',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${order.grandTotal.toStringAsFixed(0)} received via ${order.paymentMethod ?? "Cash"}',
                    style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 24),

                  // Thermal Receipt Paper Roll Preview
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Restaurant Header
                        const Text(
                          'SPICE HAVEN RESTO & BAR',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Plot 42, High Street, Baner, Pune - 411045',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                        const Text(
                          'GSTIN: 27AAAAA0000A1Z5 · FSSAI: 11521000000123',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textLight, fontSize: 10),
                        ),
                        const Divider(height: 20, thickness: 1, color: AppColors.borderMedium),

                        // Tax Invoice Metadata
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Invoice: ${order.invoiceNumber ?? order.orderNumber}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                            Text(
                              dateFormatted,
                              style: const TextStyle(color: AppColors.textLight, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              order.tableNumber != null
                                  ? 'Table: ${order.tableNumber}'
                                  : 'Type: ${order.orderTypeLabel}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                            Text(
                              'Cashier: ${order.waiterName ?? "Staff"}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                        const Divider(height: 20, thickness: 1, color: AppColors.borderMedium),

                        // Items Breakdown
                        for (var item in order.activeItems) ...[
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
                                Text(
                                  '₹${item.totalPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Divider(height: 20, thickness: 1, color: AppColors.borderMedium),

                        // Taxes & Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Subtotal', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            Text('₹${order.subtotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        if (order.computedDiscount > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Discount', style: TextStyle(fontSize: 12, color: AppColors.vegGreen)),
                              Text('−₹${order.computedDiscount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.vegGreen)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // B4: derived from the order's real tax rate.
                            Text('CGST (${(order.taxPercent / 2).toStringAsFixed(1)}%)',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            Text('₹${order.cgst.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('SGST (${(order.taxPercent / 2).toStringAsFixed(1)}%)',
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            Text('₹${order.sgst.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const Divider(height: 20, thickness: 1.5, color: AppColors.textDark),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL PAID', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            Text('₹${order.grandTotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primaryOrange)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Payment Mode', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            Text(order.paymentMethod ?? 'Cash', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const Divider(height: 24, thickness: 1, color: AppColors.borderLight),
                        const Text(
                          '*** THANK YOU FOR VISITING! ***\nPLEASE VISIT AGAIN',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textLight, fontSize: 10, letterSpacing: 0.5),
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
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
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

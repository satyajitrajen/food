import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/custom_badge.dart';
import '../modals/apply_discount_dialog.dart';
import '../modals/add_charge_dialog.dart';
import '../payment/payment_screen.dart';

class BillPreviewScreen extends StatefulWidget {
  const BillPreviewScreen({super.key});

  @override
  State<BillPreviewScreen> createState() => _BillPreviewScreenState();
}

class _BillPreviewScreenState extends State<BillPreviewScreen> {
  bool _isItemsExpanded = true;
  // Capture once — the invoice date must not drift on rebuilds.
  late final String _invoiceDateStr =
      DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final activeOrder = provider.activeOrder;

    if (activeOrder == null) {
      return const Scaffold(body: Center(child: Text('No active bill to preview')));
    }

    final invoiceDateStr = _invoiceDateStr;
    final tableName = activeOrder.tableNumber ?? provider.selectedTable?.tableNumber ?? 'Counter';

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Confirm Sale', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Invoice Number', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        Text(
                          activeOrder.orderNumber,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ],
                    ),
                    const Divider(height: 16, color: AppColors.borderLight),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Invoice Date', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        Text(invoiceDateStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    const Divider(height: 16, color: AppColors.borderLight),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Order Type', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        Text(activeOrder.orderTypeLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                    const Divider(height: 16, color: AppColors.borderLight),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Table / Counter', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                        Text('Table $tableName', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryOrange, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Billing Items Section (Expandable)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _isItemsExpanded = !_isItemsExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Text('Billing Items', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.creamSubtle,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${activeOrder.totalItemCount}',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            Icon(_isItemsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                          ],
                        ),
                      ),
                    ),
                    if (_isItemsExpanded) ...[
                      const Divider(height: 1, color: AppColors.borderLight),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: activeOrder.activeItems.length,
                        itemBuilder: (context, index) {
                          final item = activeOrder.activeItems[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                VegMark(isVeg: item.menuItem.isVeg, size: 12),
                                const SizedBox(width: 8),
                                Text(
                                  '${item.quantity} × ',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primaryOrange),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                      if (item.selectedModifiers.isNotEmpty)
                                        Text(
                                          '+ ${item.selectedModifiers.map((m) => m.name).join(", ")}',
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                                Text('₹${item.totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action Buttons: + Add Discount, + Add Tax, + Additional Charge
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ApplyDiscountDialog.show(context),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: Text(activeOrder.computedDiscount > 0 ? 'Discount: −₹${activeOrder.computedDiscount.toStringAsFixed(0)}' : '+ Discount'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => AddChargeDialog.show(context),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: const Text('+ Charges'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Bill Calculation Summary Box
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                        Text('₹${activeOrder.subtotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ],
                    ),
                    if (activeOrder.computedDiscount > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Discount (${activeOrder.discountReason ?? "Promo"})', style: const TextStyle(color: AppColors.vegGreen, fontSize: 13)),
                          Text('−₹${activeOrder.computedDiscount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.vegGreen, fontWeight: FontWeight.w700, fontSize: 13)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // B4: derive the CGST/SGST split from the real rate.
                        Text(
                          'GST (CGST ${(activeOrder.taxPercent / 2).toStringAsFixed(1)}% + SGST ${(activeOrder.taxPercent / 2).toStringAsFixed(1)}%)',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                        Text('₹${activeOrder.computedTax.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    if (activeOrder.serviceCharge > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Service Charge', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          Text('₹${activeOrder.serviceCharge.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ],
                    if (activeOrder.packagingCharge > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Packaging', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          Text('₹${activeOrder.packagingCharge.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ],
                    const Divider(height: 24, color: AppColors.borderLight),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        Text(
                          '₹${activeOrder.grandTotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            color: AppColors.primaryOrange,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Proceed to Payment CTA
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PaymentScreen()),
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Proceed to Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Text(
                        '(₹${activeOrder.grandTotal.toStringAsFixed(0)})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

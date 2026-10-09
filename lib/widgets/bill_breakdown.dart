import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme/app_theme.dart';
import '../models/order_model.dart';

/// The one bill summary used everywhere a bill is shown (preview, payment,
/// receipt): every charge that makes up the total is listed, so the lines
/// always add up to the total.
class BillBreakdown extends StatelessWidget {
  final RestaurantOrder order;

  /// Show "Paid", change and refunds below the total (receipts).
  final bool showPayment;

  const BillBreakdown({super.key, required this.order, this.showPayment = false});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final halfRate = (o.taxPercent / 2).toStringAsFixed(o.taxPercent % 2 == 0 ? 0 : 1);
    return Column(
      children: [
        _row('Subtotal', formatInr(o.subtotal)),
        if (o.computedDiscount > 0)
          _row(
            o.discountReason == null || o.discountReason!.isEmpty
                ? 'Discount'
                : 'Discount (${o.discountReason})',
            '−${formatInr(o.computedDiscount)}',
            color: AppColors.success,
          ),
        if (o.serviceCharge > 0) _row('Service charge', formatInr(o.serviceCharge)),
        if (o.taxPercent > 0) ...[
          _row('CGST $halfRate%', formatInr(o.cgst), muted: true),
          _row('SGST $halfRate%', formatInr(o.computedTax - o.cgst), muted: true),
          if (o.isTaxInclusive)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('GST included in prices',
                    style: TextStyle(fontSize: 11, color: AppColors.textLight)),
              ),
            ),
        ],
        if (o.packagingCharge > 0) _row('Packaging', formatInr(o.packagingCharge)),
        if (o.deliveryCharge > 0) _row('Delivery', formatInr(o.deliveryCharge)),
        const Divider(height: 24, color: AppColors.borderLight),
        Row(
          children: [
            const Expanded(
              child: Text('Total', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
            Text(
              formatInr(o.grandTotal),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 24,
                color: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
        if (showPayment && o.isClosed) ...[
          const SizedBox(height: 8),
          if (o.paymentSplits.length > 1)
            ...o.paymentSplits.map((leg) =>
                _row('Paid (${leg.method})', formatInr(leg.amount), muted: true))
          else if (o.paymentMethod != null)
            _row('Paid by', o.paymentMethod!, muted: true),
          if (o.totalPaid > o.grandTotal + 0.005)
            _row('Change returned', formatInr(o.totalPaid - o.grandTotal), muted: true),
          if (o.refundedAmount > 0)
            _row('Refunded', '−${formatInr(o.refundedAmount)}', color: AppColors.danger),
        ],
      ],
    );
  }

  Widget _row(String label, String value, {Color? color, bool muted = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color ?? (muted ? AppColors.textMuted : AppColors.textDark),
                  fontSize: muted ? 13 : 14,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color ?? AppColors.textDark,
                fontWeight: FontWeight.w700,
                fontSize: muted ? 13 : 14,
              ),
            ),
          ],
        ),
      );
}

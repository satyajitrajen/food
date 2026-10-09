import '../../models/kot_model.dart';
import '../../models/order_model.dart';
import '../../models/settings_model.dart';
import '../../models/shift_model.dart';
import 'esc_pos_builder.dart';

/// Renders a customer receipt as ESC/POS bytes (80mm / 32 columns).
List<int> buildReceiptBytes(RestaurantOrder order, RestaurantSettings settings) {
  final b = EscPosBuilder();
  final center = b.align(1);
  center
    ..doubleSize(true)
    ..bold(true)
    ..text(settings.restaurantName)
    ..doubleSize(false);
  if (settings.address.isNotEmpty) center.text(settings.address);
  if (settings.phone.isNotEmpty) center.text('Ph: ${settings.phone}');
  final ids = [
    if (settings.gstin.isNotEmpty) 'GSTIN: ${settings.gstin}',
    if (settings.fssai.isNotEmpty) 'FSSAI: ${settings.fssai}',
  ];
  if (ids.isNotEmpty) center.text(ids.join('  '));
  center
    ..divider()
    ..align(0);

  b
    ..text('Invoice: ${order.invoiceNumber ?? 'pending sync'}')
    ..text('Order: ${order.orderNumber}   ${order.orderTypeLabel}'
        '${order.tableNumber != null ? ' (Table ${order.tableNumber})' : ''}')
    ..text('Date: ${_stamp(order.paidAt ?? order.createdAt)}')
    ..text('Server: ${order.waiterName ?? '-'}')
    ..divider();

  for (final item in order.activeItems) {
    b.text('${item.quantity} x ${item.displayName}');
    b.align(2).text(item.totalPrice.toStringAsFixed(2)).align(0);
    for (final m in item.selectedModifiers.where((m) => m.isSelected)) {
      b.text('   + ${m.name}');
    }
    if (item.itemNote != null && item.itemNote!.isNotEmpty) {
      b.text('   * ${item.itemNote}');
    }
  }

  b.divider();
  void row(String label, String value) {
    b.align(0).text(label);
    b.align(2).text(value).align(0);
  }

  row('Subtotal', order.subtotal.toStringAsFixed(2));
  if (order.computedDiscount > 0) {
    row('Discount${order.discountReason != null ? ' (${order.discountReason})' : ''}',
        '-${order.computedDiscount.toStringAsFixed(2)}');
  }
  row('CGST (${(order.taxPercent / 2).toStringAsFixed(1)}%)', order.cgst.toStringAsFixed(2));
  row('SGST (${(order.taxPercent / 2).toStringAsFixed(1)}%)', order.sgst.toStringAsFixed(2));
  if (order.serviceCharge > 0) row('Service Charge', order.serviceCharge.toStringAsFixed(2));
  if (order.packagingCharge > 0) row('Packaging', order.packagingCharge.toStringAsFixed(2));
  if (order.deliveryCharge > 0) row('Delivery', order.deliveryCharge.toStringAsFixed(2));
  if (order.refundedAmount > 0) row('Refunded', '-${order.refundedAmount.toStringAsFixed(2)}');
  b.bold(true);
  row('TOTAL', 'Rs. ${order.grandTotal.toStringAsFixed(2)}');
  b.bold(false);
  // Split tender: one Paid row per leg; otherwise the single method line.
  final legs = order.paymentSplits;
  if (legs.length > 1) {
    for (final leg in legs) {
      row('Paid (${leg.method})', leg.amount.toStringAsFixed(2));
    }
  } else {
    row('Paid (${order.paymentMethod ?? '-'})', order.totalPaid.toStringAsFixed(2));
  }
  if (order.hasApprovalReference) b.text('Approval: ${order.paymentReference}');
  final change = order.totalPaid - order.grandTotal;
  if (change > 0.005) row('Change', change.toStringAsFixed(2));

  b
    ..divider()
    ..align(1)
    ..text('Thank you! Visit again.')
    ..feed(3)
    ..cut();
  return b.build();
}

/// Renders a kitchen order ticket as ESC/POS bytes.
List<int> buildKotBytes(KitchenOrderTicket kot, RestaurantSettings settings) {
  final b = EscPosBuilder();
  b
    ..align(1)
    ..doubleSize(true)
    ..bold(true)
    ..text('K O T')
    ..doubleSize(false)
    ..text(kot.kotNumber)
    ..bold(false)
    ..align(0)
    ..divider('=')
    ..text('Table: ${kot.tableNumber ?? '-'}   Type: ${_typeLabel(kot.orderType)}')
    ..text('Waiter: ${kot.waiterName}')
    ..text('Time: ${kot.createdAt}')
    ..divider('=');
  for (final item in kot.items.where((i) => !i.isCancelled)) {
    b.bold(true).text('${item.quantity} x ${item.displayName}').bold(false);
    for (final m in item.selectedModifiers.where((m) => m.isSelected)) {
      b.text('   + ${m.name}');
    }
    if (item.itemNote != null && item.itemNote!.isNotEmpty) {
      b.text('   ** ${item.itemNote}');
    }
  }
  if (kot.specialInstructions != null && kot.specialInstructions!.isNotEmpty) {
    b.divider('=').text('Note: ${kot.specialInstructions}');
  }
  b.feed(3).cut();
  return b.build();
}

String _typeLabel(dynamic type) {
  final name = type.toString();
  if (name.contains('takeaway')) return 'TAKEAWAY';
  if (name.contains('delivery')) return 'DELIVERY';
  return 'DINE-IN';
}

/// Small connectivity test page (printer status screen).
List<int> buildTestPageBytes() {
  final b = EscPosBuilder();
  b
    ..align(1)
    ..doubleSize(true)
    ..bold(true)
    ..text('Hishobkr POS')
    ..doubleSize(false)
    ..bold(false)
    ..divider()
    ..text('Printer test — connection OK')
    ..text('Printed: ${DateTime.now()}')
    ..feed(3)
    ..cut();
  return b.build();
}

String _stamp(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Z-report (end of shift) as ESC/POS bytes. [server] is the server's
/// Z-report when available; the terminal's own figures are printed otherwise.
List<int> buildZReportBytes(Shift shift, RestaurantSettings settings, {Map<String, dynamic>? server}) {
  final b = EscPosBuilder();
  b
    ..align(1)
    ..bold(true)
    ..text(settings.restaurantName)
    ..text('Z-REPORT')
    ..bold(false)
    ..divider()
    ..align(0);
  void row(String label, double v) {
    b.align(0).text(label);
    b.align(2).text(v.toStringAsFixed(2)).align(0);
  }

  double paise(String k) => ((server?[k] as num?)?.toDouble() ?? 0) / 100.0;
  b
    ..text('Staff: ${shift.staffName}')
    ..text('Opened: ${_stamp(shift.startedAt)}')
    ..text('Closed: ${_stamp(shift.closedAt ?? DateTime.now())}')
    ..divider();
  row('Opening cash', shift.openingCash);
  row('Cash sales', shift.cashSales);
  row('UPI sales', shift.upiSales);
  row('Card sales', shift.cardSales);
  row('Cash refunds', -shift.refundsCash);
  row('Digital refunds', -shift.refundsDigital);
  row('Expenses (cash)', -shift.expenses);
  row('Cash in', shift.cashIn);
  row('Cash out', -shift.cashOut);
  b.divider();
  final expected = server != null ? paise('expected_cash_paise') : shift.expectedCash;
  final counted = server != null ? paise('counted_cash_paise') : (shift.actualCashClosed ?? 0);
  b.bold(true);
  row('Expected cash', expected);
  row('Counted cash', counted);
  row('Difference', counted - expected);
  b.bold(false);
  if (server == null) {
    b
      ..divider()
      ..text('Offline copy - server totals pending');
  }
  if (shift.closingNotes != null && shift.closingNotes!.isNotEmpty) {
    b
      ..divider()
      ..text('Notes: ${shift.closingNotes}');
  }
  b
    ..feed(3)
    ..cut();
  return b.build();
}

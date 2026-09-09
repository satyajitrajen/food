import '../../models/kot_model.dart';
import '../../models/order_model.dart';
import '../../models/settings_model.dart';
import 'esc_pos_builder.dart';

/// Renders a customer receipt as ESC/POS bytes (80mm / 32 columns).
List<int> buildReceiptBytes(RestaurantOrder order, RestaurantSettings settings) {
  final b = EscPosBuilder();
  final center = b.align(1);
  center
    ..doubleSize(true)
    ..bold(true)
    ..text(settings.restaurantName)
    ..doubleSize(false)
    ..text(settings.address)
    ..text('GSTIN: ${settings.gstin}  FSSAI: ${settings.fssai}')
    ..divider()
    ..align(0);

  b
    ..text('Invoice: ${order.invoiceNumber ?? '-'}')
    ..text('Order: ${order.orderNumber}   ${order.orderTypeLabel}'
        '${order.tableNumber != null ? ' (Table ${order.tableNumber})' : ''}')
    ..text('Date: ${order.paidAt ?? order.createdAt}')
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
  b.bold(true);
  row('TOTAL', 'Rs. ${order.grandTotal.toStringAsFixed(2)}');
  b.bold(false);
  row('Paid (${order.paymentMethod ?? '-'})', order.totalPaid.toStringAsFixed(2));
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

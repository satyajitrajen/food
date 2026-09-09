import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/order_model.dart';
import '../../models/outlet_model.dart';
import '../../models/settings_model.dart';

/// WhatsApp bill sharing — text bill via the `wa.me` deep link.
///
/// Feasibility notes:
/// - No WhatsApp Business API needed: `https://wa.me/<number>?text=…` opens a
///   chat with the message pre-filled (WhatsApp app on phones, WhatsApp Web on
///   desktops). Works from Android/iOS/Windows/Linux/macOS/web.
/// - Deep links cannot attach files, so v1 sends the bill as formatted text.
///   PDF/image attachment would need platform share intents (+pdf/share_plus)
///   and does not exist on Windows desktop — documented as a follow-up.

/// Normalizes an Indian mobile number for wa.me: digits only, with country
/// code 91. Returns null when the number is unusable (e.g. < 10 digits).
String? normalizeWaNumber(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.length == 10) {
    return '91$digits';
  }
  if (digits.startsWith('0') && digits.length == 11) {
    return '91${digits.substring(1)}';
  }
  if (digits.length >= 11 && digits.length <= 15) {
    if (digits.startsWith('91')) return digits;
    if (digits.startsWith('0')) return digits.substring(1);
    return '91$digits';
  }
  return null;
}

/// Formats the invoice as WhatsApp text — mirrors the thermal receipt layout.
String buildWhatsAppBillText({
  required RestaurantOrder order,
  required RestaurantSettings settings,
  required Outlet outlet,
}) {
  final b = StringBuffer();
  final dateFmt = DateFormat('dd MMM yyyy · hh:mm a');
  String money(double v) => '₹${v.toStringAsFixed(2)}';

  final restaurantName =
      settings.restaurantName.isNotEmpty ? settings.restaurantName : outlet.name;
  b.writeln('🛎️ $restaurantName');
  if (settings.address.isNotEmpty) b.writeln(settings.address);
  if (settings.phone.isNotEmpty) b.writeln('Tel: ${settings.phone}');
  if (settings.gstin.isNotEmpty) b.writeln('GSTIN: ${settings.gstin}');
  b.writeAll(['', '=' * 40]);

  final billNo = order.invoiceNumber ?? order.orderNumber;
  b.writeln('Bill: $billNo');
  final when = order.paidAt ?? order.createdAt;
  b.writeln('Date: ${dateFmt.format(when)}');
  if (order.orderType == OrderType.dineIn) {
    b.writeln('Table: ${order.tableNumber ?? '-'} · Guests: ${order.guestCount}');
  } else {
    b.writeln('Type: ${order.orderType.name.toUpperCase()}');
  }
  b.writeln('Served by: ${order.waiterName ?? '-'}');
  b.writeAll(['', '=' * 40]);

  for (final item in order.items.where((i) => !i.isCancelled)) {
    final variant = item.selectedVariant?.name != null ? ' (${item.selectedVariant!.name})' : '';
    b.writeln('${item.quantity} × ${item.menuItem.name}$variant');
    final mods = item.selectedModifiers.where((m) => m.isSelected).toList();
    if (mods.isNotEmpty) {
      for (final m in mods) {
        final plus = m.price > 0 ? ' (+${money(m.price)})' : '';
        b.writeln('   • ${m.name}$plus');
      }
    }
    if (item.itemNote != null && item.itemNote!.isNotEmpty) {
      b.writeln('   Note: ${item.itemNote}');
    }
    b.writeln('   ${money(item.unitPrice * item.quantity)}');
  }
  b.writeAll(['', '-' * 40]);

  b.writeln('Subtotal:        ${money(order.subtotal)}');
  if (order.computedDiscount > 0) {
    b.writeln('Discount:        -${money(order.computedDiscount)}'
        '${order.discountReason != null && order.discountReason!.isNotEmpty ? ' (${order.discountReason})' : ''}');
  }
  if (order.serviceCharge > 0) {
    b.writeln('Service Charge:  ${money(order.serviceCharge)}');
  }
  if (order.packagingCharge > 0) {
    b.writeln('Packaging:       ${money(order.packagingCharge)}');
  }
  if (order.deliveryCharge > 0) {
    b.writeln('Delivery:        ${money(order.deliveryCharge)}');
  }
  if (order.isTaxInclusive) {
    b.writeln('Incl. GST (${order.taxPercent.toStringAsFixed(1)}%)');
  } else if (order.computedTax > 0) {
    b.writeln('CGST:            ${money(order.cgst)}');
    b.writeln('SGST:            ${money(order.sgst)}');
  }
  b.writeAll(['', '=' * 40]);
  b.writeln('GRAND TOTAL: ${money(order.grandTotal)}');
  if (order.totalPaid > 0) {
    b.writeln('Paid via ${order.paymentMethod?.toUpperCase() ?? '-'}: ${money(order.totalPaid)}');
  }
  b.writeAll(['', 'Thank you! Please visit again 🙏', restaurantName]);
  return b.toString();
}

/// Opens WhatsApp (app or Web) with the bill text. Returns false when the
/// number is unusable; throws when the launcher fails.
Future<bool> shareBillOnWhatsApp({
  required RestaurantOrder order,
  required RestaurantSettings settings,
  required Outlet outlet,
  required String phone,
}) async {
  final number = normalizeWaNumber(phone);
  if (number == null) return false;
  final text = buildWhatsAppBillText(order: order, settings: settings, outlet: outlet);
  final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Reusable SnackBar feedback for the share attempt.
void showShareResult(BuildContext context, bool ok) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(
    content: Text(ok
        ? 'Opening WhatsApp with your bill…'
        : 'Could not open WhatsApp. Check the customer number and WhatsApp is installed.'),
    duration: const Duration(seconds: 3),
  ));
}

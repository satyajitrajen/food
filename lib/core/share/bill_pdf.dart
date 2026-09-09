import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../models/order_model.dart';
import '../../models/settings_model.dart';

/// Renders a printable PDF bill for the customer and shares it via the OS
/// share sheet (WhatsApp on Android/iOS). On Windows desktop file sharing is
/// not supported by share_plus, so it falls back to surfacing the saved path.
class BillShare {
  static Future<Uint8List> buildReceiptPdf(
    RestaurantOrder order,
    RestaurantSettings settings,
  ) async {
    final doc = pw.Document();
    // Built-in PDF fonts are Latin-1 only — no ₹ glyph (same reason the
    // ESC/POS layer maps it to "Rs.").
    String money(double v) => 'Rs. ${v.toStringAsFixed(2)}';
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Center(
            child: pw.Text(settings.restaurantName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          ),
          if (settings.address.isNotEmpty)
            pw.Center(
                child: pw.Text(settings.address, style: const pw.TextStyle(fontSize: 8))),
          if (settings.gstin.isNotEmpty)
            pw.Center(
                child: pw.Text('GSTIN: ${settings.gstin}', style: const pw.TextStyle(fontSize: 7))),
          pw.Divider(),
          pw.Text(
            '${order.invoiceNumber ?? order.orderNumber} · ${dateFmt.format(order.paidAt ?? order.createdAt)}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            '${order.orderTypeLabel}${order.tableNumber != null ? ' · Table ${order.tableNumber}' : ''} · '
            'Waiter: ${order.waiterName ?? "-"}',
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.Divider(),
          ...order.activeItems.map((item) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text('${item.quantity} × ${item.displayName}',
                        style: const pw.TextStyle(fontSize: 9)),
                  ),
                  pw.Text(money(item.totalPrice), style: const pw.TextStyle(fontSize: 9)),
                ],
              )),
          pw.Divider(),
          _row('Subtotal', money(order.subtotal)),
          if (order.computedDiscount > 0) _row('Discount', '-${money(order.computedDiscount)}'),
          if (!order.isTaxInclusive && order.computedTax > 0) ...[
            _row('CGST', money(order.cgst)),
            _row('SGST', money(order.sgst)),
          ],
          if (order.isTaxInclusive)
            _row('Incl. GST (${order.taxPercent.toStringAsFixed(1)}%)', ''),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL PAID',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Text(money(order.grandTotal),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
          pw.Text('Paid via ${order.paymentMethod ?? "Cash"}',
              style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(),
          pw.Center(child: pw.Text('*** THANK YOU! ***', style: const pw.TextStyle(fontSize: 8))),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _row(String label, String value) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label), pw.Text(value)],
      );

  /// Saves + shares the PDF. Returns null on success; otherwise a message.
  static Future<String?> sharePdfBill(
    RestaurantOrder order,
    RestaurantSettings settings,
  ) async {
    final bytes = await buildReceiptPdf(order, settings);
    final dir = await getTemporaryDirectory();
    final safeName =
        (order.invoiceNumber ?? order.orderNumber).replaceAll(RegExp(r'\W'), '_');
    final file = File('${dir.path}/$safeName.pdf');
    await file.writeAsBytes(bytes, flush: true);

    try {
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Bill ${order.invoiceNumber ?? order.orderNumber}',
      );
      if (result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.dismissed) {
        return null;
      }
    } catch (_) {
      // platform without file sharing → report the saved path
    }
    return 'PDF saved at ${file.path} (share not available on this platform).';
  }
}

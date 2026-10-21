import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// One line of a report section (a tender, a category, a waiter...).
class ReportRow {
  final String label;
  final double amount;
  final int count;

  const ReportRow(this.label, this.amount, {this.count = 0});
}

/// The figures behind one view of the Reports screen, flattened so the PDF
/// renderer needs no knowledge of server/local fallbacks or filters.
class ReportSnapshot {
  final String restaurantName;
  final String periodLabel;
  final String typeLabel;
  final int orderCount;
  final double grossSales;
  final double refunds;
  final double netSales;
  final double totalExpenses;
  final double estimatedProfit;
  final double aov;
  /// True under an order-type filter, where expenses/profit are not
  /// attributable and render as an em dash.
  final bool typeFiltered;
  final List<ReportRow> salesByType;
  final List<ReportRow> salesByTender;
  final List<ReportRow> topCategories;
  final List<ReportRow> topItems;
  final List<ReportRow> staffSales;
  final List<ReportRow> expensesByCategory;

  const ReportSnapshot({
    required this.restaurantName,
    required this.periodLabel,
    required this.typeLabel,
    required this.orderCount,
    required this.grossSales,
    required this.refunds,
    required this.netSales,
    required this.totalExpenses,
    required this.estimatedProfit,
    required this.aov,
    required this.typeFiltered,
    required this.salesByType,
    required this.salesByTender,
    required this.topCategories,
    required this.topItems,
    required this.staffSales,
    required this.expensesByCategory,
  });
}

/// Renders the Reports screen selection as a shareable A4 PDF. Same
/// save-and-share flow as the bill PDF; on platforms without the share
/// sheet the saved path is surfaced instead.
class ReportPdf {
  static Future<Uint8List> buildPdf(ReportSnapshot r) async {
    final doc = pw.Document();
    // Built-in PDF fonts are Latin-1 only — no ₹ glyph (same as the bill).
    String money(double v) => 'Rs. ${v.toStringAsFixed(2)}';
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

    pw.Widget section(String title, List<pw.Widget> rows) => rows.isEmpty
        ? pw.SizedBox()
        : pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
                child: pw.Text(title.toUpperCase(),
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 10, letterSpacing: 1)),
              ),
              pw.Container(
                decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400))),
                child: pw.Column(children: rows),
              ),
            ],
          );

    pw.Widget amountRow(String label, String value, {bool bold = false}) {
      final style = pw.TextStyle(
          fontSize: 9.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ]),
      );
    }

    pw.Widget countRow(ReportRow row) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Expanded(child: pw.Text(row.label, style: const pw.TextStyle(fontSize: 9.5))),
            pw.Text(row.count > 0 ? '${row.count}' : '',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(width: 24),
            pw.Text(money(row.amount),
                style: pw.TextStyle(
                    fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
          ]),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Center(
            child: pw.Text(r.restaurantName,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          ),
          pw.Center(
            child: pw.Text('SALES REPORT',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 2,
                    color: PdfColors.grey700)),
          ),
          pw.Center(
            child: pw.Text('${r.periodLabel} · ${r.typeLabel}',
                style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.Center(
            child: pw.Text('Downloaded: ${dateFmt.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ),
          pw.Divider(),
          amountRow('Orders', '${r.orderCount}', bold: true),
          amountRow('Gross sales', money(r.grossSales)),
          if (r.refunds > 0) amountRow('Refunds', '-${money(r.refunds)}'),
          amountRow('Net sales', money(r.netSales), bold: true),
          amountRow('Average order value', money(r.aov)),
          if (!r.typeFiltered) amountRow('Expenses', money(r.totalExpenses)),
          if (!r.typeFiltered)
            amountRow('Estimated profit', money(r.estimatedProfit), bold: true),
          if (r.typeFiltered)
            pw.Text('Expenses and profit are not attributed by order type.',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          section('Sales by Order Type',
              r.salesByType.map((e) => amountRow(e.label, money(e.amount))).toList()),
          section('Payment Mode Distribution',
              r.salesByTender.map((e) => amountRow(e.label, money(e.amount))).toList()),
          section('Top Performing Categories',
              r.topCategories.map(countRow).toList()),
          section('Top Selling Items', r.topItems.map(countRow).toList()),
          section('Staff Performance', r.staffSales.map(countRow).toList()),
          section('Expenses by Category',
              r.expensesByCategory.map((e) => amountRow(e.label, money(e.amount))).toList()),
          pw.Divider(),
          pw.Center(
            child: pw.Text('Generated by Hishobkr',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Saves + shares the PDF. Returns null on success; otherwise a message.
  static Future<String?> share(ReportSnapshot r) async {
    final bytes = await buildPdf(r);
    final dateFmt = DateFormat('yyyyMMdd');
    final safeName = '${r.restaurantName}_report_${dateFmt.format(DateTime.now())}'
        .replaceAll(RegExp(r'\W'), '_');

    // No filesystem on the web build — hand the bytes straight to the
    // share sheet (browser offers share/download).
    if (kIsWeb) {
      try {
        final result = await Share.shareXFiles([
          XFile.fromData(bytes, mimeType: 'application/pdf', name: '$safeName.pdf'),
        ], subject: 'Sales report — ${r.periodLabel}');
        if (result.status == ShareResultStatus.success ||
            result.status == ShareResultStatus.dismissed) {
          return null;
        }
        return 'Report PDF ready.';
      } catch (_) {
        return 'Report PDF generated ($safeName.pdf).';
      }
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$safeName.pdf');
    await file.writeAsBytes(bytes, flush: true);

    try {
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Sales report — ${r.periodLabel}',
      );
      if (result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.dismissed) {
        return null;
      }
    } catch (_) {
      // platform without file sharing → report the saved path
    }
    return 'Report PDF saved at ${file.path} (share not available on this platform).';
  }
}

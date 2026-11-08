import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'printing.dart';

/// One printed line recovered from our ESC/POS output.
class EscPosLine {
  final String text;
  final int align; // 0 left, 1 center, 2 right
  final bool bold;
  final bool large;
  const EscPosLine(this.text, {this.align = 0, this.bold = false, this.large = false});
}

/// Decodes the small ESC/POS subset [EscPosBuilder] emits (init, align, bold,
/// double size, text + LF, feed, cut) back into styled lines, so the same
/// receipt can be rendered as a PDF for non-thermal printers.
List<EscPosLine> decodeEscPos(List<int> bytes) {
  final lines = <EscPosLine>[];
  final text = <int>[];
  var align = 0;
  var bold = false;
  var large = false;
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x1B && i + 1 < bytes.length) {
      final cmd = bytes[i + 1];
      if (cmd == 0x40) {
        align = 0;
        bold = false;
        large = false;
        i += 2;
        continue;
      }
      if (cmd == 0x61 && i + 2 < bytes.length) {
        align = bytes[i + 2];
        i += 3;
        continue;
      }
      if (cmd == 0x45 && i + 2 < bytes.length) {
        bold = bytes[i + 2] != 0;
        i += 3;
        continue;
      }
      i += 2;
      continue;
    }
    if (b == 0x1D && i + 1 < bytes.length) {
      final cmd = bytes[i + 1];
      if (cmd == 0x21 && i + 2 < bytes.length) {
        large = bytes[i + 2] != 0;
        i += 3;
        continue;
      }
      if (cmd == 0x56) {
        i += 4; // cut: GS V m n
        continue;
      }
      i += 2;
      continue;
    }
    if (b == 0x0A) {
      lines.add(EscPosLine(latin1.decode(text), align: align, bold: bold, large: large));
      text.clear();
      i++;
      continue;
    }
    text.add(b);
    i++;
  }
  if (text.isNotEmpty) {
    lines.add(EscPosLine(latin1.decode(text), align: align, bold: bold, large: large));
  }
  // Trailing paper feed is meaningless on a page.
  while (lines.isNotEmpty && lines.last.text.trim().isEmpty) {
    lines.removeLast();
  }
  return lines;
}

/// Prints through the OS print dialog (AirPrint on iOS/macOS, the Android
/// print service, the browser on web): works with any office, A4 or label
/// printer the device can already see.
class SystemPrinter implements PrinterAdapter {
  final int paperMm;
  SystemPrinter({this.paperMm = 58});

  @override
  String get name => 'System print';

  @override
  Future<void> send(List<int> bytes) async {
    final lines = decodeEscPos(bytes);
    final doc = await buildReceiptPdf(lines, paperMm: paperMm);
    await Printing.layoutPdf(
      name: 'Hishobkr receipt',
      format: doc.format,
      onLayout: (_) async => doc.bytes,
    );
  }
}

class ReceiptPdf {
  final PdfPageFormat format;
  final Uint8List bytes;
  const ReceiptPdf(this.format, this.bytes);
}

/// Lays the decoded lines out on a roll-width page in a monospace font.
Future<ReceiptPdf> buildReceiptPdf(List<EscPosLine> lines, {int paperMm = 58}) async {
  const fontSize = 8.0;
  const lineHeight = fontSize * 1.35;
  final margin = 3 * PdfPageFormat.mm;
  final width = paperMm * PdfPageFormat.mm;
  var height = margin * 2;
  for (final l in lines) {
    height += l.large ? lineHeight * 2 : lineHeight;
  }
  final format = PdfPageFormat(width, height, marginAll: margin);
  final regular = pw.Font.courier();
  final boldFont = pw.Font.courierBold();
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: format,
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (final l in lines)
          pw.Text(
            l.text,
            textAlign: switch (l.align) {
              1 => pw.TextAlign.center,
              2 => pw.TextAlign.right,
              _ => pw.TextAlign.left,
            },
            style: pw.TextStyle(
              font: l.bold || l.large ? boldFont : regular,
              fontSize: l.large ? fontSize * 1.8 : fontSize,
              lineSpacing: 0,
            ),
          ),
      ],
    ),
  ));
  return ReceiptPdf(format, await doc.save());
}

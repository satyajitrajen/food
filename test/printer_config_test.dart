import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/printing/printing.dart';
import 'package:food_pos/core/printing/receipt_builder.dart';

void main() {
  group('PrinterConfig', () {
    test('keeps the old network and Bluetooth shapes', () {
      final net = PrinterConfig.parse('192.168.1.50:9100');
      expect(net.kind, PrinterKind.network);
      expect(net.address, '192.168.1.50:9100');
      expect(net.paperMm, 58);
      final bt = PrinterConfig.parse('bt:AA:BB:CC:DD:EE:FF');
      expect(bt.kind, PrinterKind.bluetooth);
      expect(bt.address, 'AA:BB:CC:DD:EE:FF');
    });

    test('parses the new kinds and the 80 mm suffix', () {
      expect(PrinterConfig.parse('ble:5A1C-77#80').kind, PrinterKind.ble);
      expect(PrinterConfig.parse('ble:5A1C-77#80').paperMm, 80);
      expect(PrinterConfig.parse('usb:1155:22304').address, '1155:22304');
      expect(PrinterConfig.parse('usb:abc').kind, PrinterKind.none);
      expect(PrinterConfig.parse('builtin').kind, PrinterKind.builtin);
      expect(PrinterConfig.parse('system#80').columns, 48);
      expect(PrinterConfig.parse('').isConfigured, isFalse);
      expect(PrinterConfig.parse('EPSON (Counter)').kind, PrinterKind.none);
    });

    test('round-trips through encode', () {
      for (final s in [
        '192.168.1.50:9100',
        'bt:AA:BB:CC:DD:EE:FF#80',
        'ble:X1',
        'usb:1:2#80',
        'builtin',
        'system',
      ]) {
        expect(PrinterConfig.parse(s).encode(), s);
      }
    });

    test('only network printers are shared per outlet', () {
      expect(PrinterConfig.parse('192.168.1.5:9100').isDeviceLocal, isFalse);
      expect(PrinterConfig.parse('ble:X1').isDeviceLocal, isTrue);
      expect(PrinterConfig.parse('system').isDeviceLocal, isTrue);
      expect(PrinterConfig.none.isDeviceLocal, isFalse);
    });
  });

  test('printerFromSetting routes every kind', () {
    expect(printerFromSetting('ble:X1').name, contains('Bluetooth LE'));
    expect(printerFromSetting('usb:1:2').name, contains('USB'));
    expect(printerFromSetting('builtin').name, 'Built-in printer');
    expect(printerFromSetting('system#80'), isA<SystemPrinter>());
    expect((printerFromSetting('system#80') as SystemPrinter).paperMm, 80);
  });

  test('80 mm dividers use 48 columns', () {
    final narrow = decodeEscPos(EscPosBuilder().divider().build());
    final wide = decodeEscPos(EscPosBuilder(columns: 48).divider().build());
    expect(narrow.single.text.length, 32);
    expect(wide.single.text.length, 48);
  });

  test('decodeEscPos recovers styled lines from a test page', () {
    final lines = decodeEscPos(buildTestPageBytes(columns: 48));
    expect(lines.first.text, 'Hishobkr POS');
    expect(lines.first.align, 1);
    expect(lines.first.bold, isTrue);
    expect(lines.first.large, isTrue);
    expect(lines[1].large, isFalse);
    expect(lines.any((l) => l.text == '-' * 48), isTrue);
    expect(lines.last.text.trim(), isNotEmpty); // trailing feed trimmed
  });

  test('buildReceiptPdf lays out a roll-width page', () async {
    final pdf = await buildReceiptPdf(decodeEscPos(buildTestPageBytes()), paperMm: 80);
    expect(pdf.bytes.length, greaterThan(500));
    expect(pdf.format.width, closeTo(80 * 72 / 25.4, 0.5));
  });
}

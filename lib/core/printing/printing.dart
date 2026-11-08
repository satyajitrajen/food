export 'esc_pos_builder.dart';
export 'printer_config.dart';
export 'printer_stub.dart' if (dart.library.io) 'printer_io.dart';
export 'system_printer.dart';

import 'printer_config.dart';
import 'printer_stub.dart' if (dart.library.io) 'printer_io.dart' as impl;
import 'system_printer.dart';

/// Pluggable printer transport (PRD P5.1): receipts and KOTs render to
/// ESC/POS bytes; an adapter delivers them to hardware.
abstract class PrinterAdapter {
  String get name;
  Future<void> send(List<int> bytes);
}

/// No-op adapter used when no printer is configured (or on web).
class NullPrinter implements PrinterAdapter {
  @override
  String get name => 'None';

  /// No printer configured: fail loudly so callers never report a print
  /// that did not happen.
  @override
  Future<void> send(List<int> bytes) async {
    throw const PrinterNotConfigured();
  }
}

class PrinterNotConfigured implements Exception {
  const PrinterNotConfigured();
  @override
  String toString() =>
      'No printer configured. Add one in Settings → Printers.';
}

/// Thrown when a Bluetooth printer is selected on a device that cannot do
/// classic-Bluetooth SPP (web, iOS, desktop).
class BluetoothUnsupportedPlatform implements Exception {
  const BluetoothUnsupportedPlatform();
  @override
  String toString() =>
      'Bluetooth printing is only available on Android. Use a network (IP:port) printer on this device.';
}

/// Chooses a printer from a settings string (see [PrinterConfig] for the
/// accepted shapes: "host:port", "bt:MAC", "ble:id", "usb:vid:pid",
/// "builtin", "system", each optionally suffixed "#80"). Returns NullPrinter
/// when unset or malformed.
PrinterAdapter printerFromSetting(String setting) =>
    printerFromConfig(PrinterConfig.parse(setting));

PrinterAdapter printerFromConfig(PrinterConfig c) {
  switch (c.kind) {
    case PrinterKind.none:
      return NullPrinter();
    case PrinterKind.network:
      final parts = c.address.split(':');
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100;
      return impl.createNetworkPrinter(parts[0], port);
    case PrinterKind.bluetooth:
      return impl.createBluetoothPrinter(c.address);
    case PrinterKind.ble:
      return impl.createBlePrinter(c.address);
    case PrinterKind.usb:
      final parts = c.address.split(':');
      return impl.createUsbPrinter(int.parse(parts[0]), int.parse(parts[1]));
    case PrinterKind.builtin:
      return impl.createBuiltinPrinter();
    case PrinterKind.system:
      return SystemPrinter(paperMm: c.paperMm);
  }
}

/// Maps raw print/transport errors to staff-readable text: network-level
/// failures get actionable copy naming the printer; anything else passes
/// through untouched.
String friendlyPrintError(String printerName, Object error) {
  final raw = '$error';
  if (raw.contains('SocketException') ||
      raw.contains('timed out') ||
      raw.contains('Connection refused')) {
    return 'Couldn\'t reach printer "$printerName". '
        'Check the network / IP:port in Settings → Printers.';
  }
  // A wrong-platform complaint (web/desktop + bt: address) already explains
  // itself; rewriting it as a connectivity problem would mislead staff.
  if (raw.contains('only available on Android') ||
      raw.contains('USB printer') ||
      raw.contains('built-in printer') ||
      raw.contains('Bluetooth LE printer')) {
    return raw;
  }
  // flutter_bluetooth_serial surfaces printer-off / out-of-range / unpaired
  // as raw IOExceptions ('device not found', 'socket connection not
  // established', 'read failed, socket might closed or timeout').
  if (raw.contains('Bluetooth') ||
      raw.contains('paired') ||
      raw.contains('device not found') ||
      raw.contains('socket') ||
      raw.contains('read failed') ||
      raw.contains('timeout')) {
    return 'Couldn\'t connect to Bluetooth printer "$printerName". '
        'Make sure it\'s powered on and paired in the device\'s Bluetooth settings.';
  }
  return raw;
}

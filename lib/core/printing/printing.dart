export 'esc_pos_builder.dart';
export 'printer_stub.dart' if (dart.library.io) 'printer_io.dart';

import 'printer_stub.dart' if (dart.library.io) 'printer_io.dart' as impl;

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
  String toString() => 'No printer configured. Add it in Settings → Printers (IP:port).';
}

/// Chooses a printer from a settings string shaped "host:port".
/// Returns NullPrinter when unset.
PrinterAdapter printerFromSetting(String setting) {
  final trimmed = setting.trim();
  if (trimmed.isEmpty || !trimmed.contains(':')) return NullPrinter();
  final parts = trimmed.split(':');
  final port = int.tryParse(parts[1]) ?? 9100;
  return impl.createNetworkPrinter(parts[0], port);
}

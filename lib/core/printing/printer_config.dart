/// How a printer is reached. The settings string keeps the old shapes
/// ("host:port", "bt:MAC") so existing outlets keep printing unchanged.
enum PrinterKind { none, network, bluetooth, ble, usb, builtin, system }

/// One configured printer: the transport, its address and the paper width.
///
/// Encoded as `<target>[#80]`, where target is one of
///   `192.168.1.50:9100`   network (raw TCP, usually port 9100)
///   `bt:AA:BB:CC:DD:EE:FF` classic Bluetooth SPP (Android)
///   `ble:<device id>`      Bluetooth Low Energy (Android + iOS)
///   `usb:<vendorId>:<productId>` USB printer on an Android host port
///   `builtin`              printer inside a Sunmi POS terminal
///   `system`               AirPrint / Android print service (PDF)
/// and `#80` marks 80 mm paper (58 mm when absent).
class PrinterConfig {
  final PrinterKind kind;

  /// Transport address: host:port, MAC, BLE id or "vid:pid"; empty for
  /// builtin/system.
  final String address;

  /// Paper width in millimetres: 58 or 80.
  final int paperMm;

  const PrinterConfig(this.kind, {this.address = '', this.paperMm = 58});

  static const none = PrinterConfig(PrinterKind.none);

  /// Characters per line in the normal font.
  int get columns => paperMm == 80 ? 48 : 32;

  bool get isConfigured => kind != PrinterKind.none;

  /// Network printers are reachable from every terminal in the outlet; the
  /// rest belong to the device they are paired or plugged into.
  bool get isDeviceLocal =>
      kind != PrinterKind.network && kind != PrinterKind.none;

  static PrinterConfig parse(String raw) {
    var s = raw.trim();
    var paper = 58;
    final hash = s.lastIndexOf('#');
    if (hash >= 0) {
      if (s.substring(hash + 1).trim() == '80') paper = 80;
      s = s.substring(0, hash).trim();
    }
    if (s.isEmpty) return none;
    final lower = s.toLowerCase();
    String rest(int n) => s.substring(n).trim();
    if (lower.startsWith('bt:')) {
      final a = rest(3);
      return a.isEmpty ? none : PrinterConfig(PrinterKind.bluetooth, address: a, paperMm: paper);
    }
    if (lower.startsWith('ble:')) {
      final a = rest(4);
      return a.isEmpty ? none : PrinterConfig(PrinterKind.ble, address: a, paperMm: paper);
    }
    if (lower.startsWith('usb:')) {
      final a = rest(4);
      return RegExp(r'^\d+:\d+$').hasMatch(a)
          ? PrinterConfig(PrinterKind.usb, address: a, paperMm: paper)
          : none;
    }
    if (lower == 'builtin') return PrinterConfig(PrinterKind.builtin, paperMm: paper);
    if (lower == 'system') return PrinterConfig(PrinterKind.system, paperMm: paper);
    if (!s.contains(':')) return none;
    return PrinterConfig(PrinterKind.network, address: s, paperMm: paper);
  }

  String encode() {
    final target = switch (kind) {
      PrinterKind.none => '',
      PrinterKind.network => address,
      PrinterKind.bluetooth => 'bt:$address',
      PrinterKind.ble => 'ble:$address',
      PrinterKind.usb => 'usb:$address',
      PrinterKind.builtin => 'builtin',
      PrinterKind.system => 'system',
    };
    if (target.isEmpty) return '';
    return paperMm == 80 ? '$target#80' : target;
  }

  /// Short human label for settings and status screens.
  String get label => switch (kind) {
        PrinterKind.none => 'Not set',
        PrinterKind.network => 'Network $address',
        PrinterKind.bluetooth => 'Bluetooth $address',
        PrinterKind.ble => 'Bluetooth LE $address',
        PrinterKind.usb => 'USB $address',
        PrinterKind.builtin => 'Built-in printer',
        PrinterKind.system => 'System print (AirPrint / Android)',
      };
}

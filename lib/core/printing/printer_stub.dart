import 'printing.dart';

/// Web has no raw TCP sockets; the adapter degrades to a no-op there.
class NetworkPrinter implements PrinterAdapter {
  final String host;
  final int port;

  NetworkPrinter(this.host, this.port);

  @override
  String get name => '$host:$port (unsupported on web)';

  @override
  Future<void> send(List<int> bytes) async {
    throw UnsupportedError('Network printing is not available in the web app');
  }
}

NetworkPrinter createNetworkPrinter(String host, int port) => NetworkPrinter(host, port);

/// Web has no Bluetooth either.
class BluetoothPrinter implements PrinterAdapter {
  final String address;

  BluetoothPrinter(this.address);

  @override
  String get name => 'Bluetooth $address (unsupported on web)';

  @override
  Future<void> send(List<int> bytes) async {
    throw UnsupportedError('Bluetooth printing is not available in the web app');
  }
}

BluetoothPrinter createBluetoothPrinter(String address) => BluetoothPrinter(address);

class _Unsupported implements PrinterAdapter {
  @override
  final String name;
  _Unsupported(this.name);

  @override
  Future<void> send(List<int> bytes) async {
    throw UnsupportedError('$name is not available in the web app. Use System print.');
  }
}

PrinterAdapter createBlePrinter(String deviceId) => _Unsupported('Bluetooth LE printing');
PrinterAdapter createUsbPrinter(int vendorId, int productId) => _Unsupported('USB printing');
PrinterAdapter createBuiltinPrinter() => _Unsupported('Built-in printing');

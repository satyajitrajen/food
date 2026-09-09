import 'printing.dart';

/// Web has no raw TCP sockets; the adapter degrades to a no-op there.
class NetworkPrinter implements PrinterAdapter {
  final String host;
  final int port;

  NetworkPrinter(this.host, this.port);

  @override
  String get name => '$host:$port (unsupported on web)';

  @override
  Future<void> send(List<int> bytes) async {}
}

NetworkPrinter createNetworkPrinter(String host, int port) => NetworkPrinter(host, port);

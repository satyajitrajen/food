import 'dart:io';

import 'printing.dart';

/// TCP raw-9100 printer transport for desktop/mobile (not available on web).
class NetworkPrinter implements PrinterAdapter {
  final String host;
  final int port;

  NetworkPrinter(this.host, this.port);

  @override
  String get name => '$host:$port';

  @override
  Future<void> send(List<int> bytes) async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
    try {
      socket.add(bytes);
      await socket.flush();
    } finally {
      socket.destroy();
    }
  }
}

NetworkPrinter createNetworkPrinter(String host, int port) => NetworkPrinter(host, port);

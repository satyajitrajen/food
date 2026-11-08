import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import 'printing.dart';

/// Serialises jobs per printer key: adapters are rebuilt from settings on
/// every use, so rapid KOTs would otherwise race their connects.
final Map<String, Future<void>> _queues = {};

Future<void> _serialised(String key, Future<void> Function() run) async {
  final previous = _queues[key];
  if (previous != null) await previous.catchError((Object _) {});
  final job = run();
  _queues[key] = job;
  try {
    await job;
  } finally {
    if (identical(_queues[key], job)) _queues.remove(key);
  }
}

/// Classic-Bluetooth SPP transport for portable thermal printers (Android
/// only; iOS needs MFi certification for classic Bluetooth, so it stays on
/// the network transport there).
class BluetoothPrinter implements PrinterAdapter {
  final String address;

  /// One in-flight operation per printer address. Adapters are rebuilt from
  /// settings on every use, so the guard is static and keyed by address —
  /// otherwise rapid KOTs would race their native connects against the same
  /// device.
  static final Map<String, Future<void>> _inflight = {};

  BluetoothPrinter(this.address);

  @override
  String get name => 'Bluetooth $address';

  @override
  Future<void> send(List<int> bytes) async {
    if (!Platform.isAndroid) {
      throw const BluetoothUnsupportedPlatform();
    }
    final previous = _inflight[address];
    if (previous != null) {
      await previous.catchError((Object _) {});
    }
    final job = _run(bytes);
    _inflight[address] = job;
    try {
      await job;
    } finally {
      if (identical(_inflight[address], job)) _inflight.remove(address);
    }
  }

  Future<void> _run(List<int> bytes) async {
    // The plugin has no cancel: on timeout the native connect keeps running,
    // so keep the future and close the connection whenever it does come up.
    final connect =
        BluetoothConnection.toAddress(address).timeout(const Duration(seconds: 6));
    final BluetoothConnection connection;
    try {
      connection = await connect;
    } on TimeoutException {
      connect.then((c) => c.finish()).catchError((Object _) {});
      rethrow;
    }
    try {
      connection.output.add(Uint8List.fromList(bytes));
      await connection.output.allSent.timeout(const Duration(seconds: 6));
    } finally {
      // A close failure must not mask the send error.
      try {
        await connection.finish();
      } catch (_) {}
    }
  }
}

// BluetoothUnsupportedPlatform lives in printing.dart next to the other
// shared exception types.


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

BluetoothPrinter createBluetoothPrinter(String address) => BluetoothPrinter(address);

/// Shared BLE client; the plugin is meant to be used as a singleton.
final FlutterReactiveBle bleClient = FlutterReactiveBle();

/// Bluetooth Low Energy transport for thermal printers that expose a GATT
/// write characteristic (most cheap 58/80 mm portables). Works on Android
/// and iOS, unlike classic SPP which iOS blocks without MFi.
class BlePrinter implements PrinterAdapter {
  final String deviceId;
  BlePrinter(this.deviceId);

  /// Printer write services seen on common models, tried before any other
  /// writable characteristic.
  static final _preferred = [
    Uuid.parse('18f0'),
    Uuid.parse('e7810a71-73ae-499d-8c15-faa9aef0c3f2'),
    Uuid.parse('49535343-fe7d-4ae5-8fa9-9fafd205e455'),
    Uuid.parse('ff00'),
  ];

  @override
  String get name => 'Bluetooth LE $deviceId';

  @override
  Future<void> send(List<int> bytes) =>
      _serialised('ble:$deviceId', () => _run(bytes));

  Future<void> _run(List<int> bytes) async {
    final connected = Completer<void>();
    final sub = bleClient
        .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 8))
        .listen((u) {
      if (u.connectionState == DeviceConnectionState.connected && !connected.isCompleted) {
        connected.complete();
      } else if (u.connectionState == DeviceConnectionState.disconnected &&
          !connected.isCompleted) {
        connected.completeError(StateError(
            'Bluetooth LE printer is off or out of range. Turn it on and try again.'));
      }
    }, onError: (Object e) {
      if (!connected.isCompleted) connected.completeError(e);
    });
    try {
      await connected.future.timeout(const Duration(seconds: 10));
      await bleClient.discoverAllServices(deviceId);
      final services = await bleClient.getDiscoveredServices(deviceId);
      final target = _pickCharacteristic(services);
      if (target == null) {
        throw StateError(
            'This Bluetooth LE device has no printer channel. Pick the printer itself, not a phone or headset.');
      }
      var chunk = Platform.isIOS ? 100 : 20;
      if (Platform.isAndroid) {
        try {
          chunk = (await bleClient.requestMtu(deviceId: deviceId, mtu: 185)) - 3;
        } catch (_) {}
      }
      final withResponse = !target.isWritableWithoutResponse;
      for (var i = 0; i < bytes.length; i += chunk) {
        final end = i + chunk < bytes.length ? i + chunk : bytes.length;
        await target.write(bytes.sublist(i, end), withResponse: withResponse);
        // Small printers have tiny buffers; pacing avoids dropped bytes.
        if (!withResponse) await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    } finally {
      await sub.cancel(); // cancelling the connection stream disconnects
    }
  }

  Characteristic? _pickCharacteristic(List<Service> services) {
    bool writable(Characteristic c) => c.isWritableWithoutResponse || c.isWritableWithResponse;
    for (final id in _preferred) {
      for (final s in services.where((s) => s.id == id)) {
        final c = s.characteristics.where(writable).firstOrNull;
        if (c != null) return c;
      }
    }
    for (final s in services) {
      final c = s.characteristics.where(writable).firstOrNull;
      if (c != null) return c;
    }
    return null;
  }
}

BlePrinter createBlePrinter(String deviceId) => BlePrinter(deviceId);

/// Native bridge in MainActivity.kt (Android USB host API).
const usbPrinterChannel = MethodChannel('hishobkr/usb_printer');

/// USB thermal printer on an Android tablet's host/OTG port, written to over
/// the printer's bulk-OUT endpoint.
class UsbPrinter implements PrinterAdapter {
  final int vendorId;
  final int productId;
  UsbPrinter(this.vendorId, this.productId);

  @override
  String get name => 'USB printer $vendorId:$productId';

  @override
  Future<void> send(List<int> bytes) => _serialised('usb:$vendorId:$productId', () async {
        if (!Platform.isAndroid) {
          throw const BluetoothUnsupportedPlatform();
        }
        try {
          await usbPrinterChannel.invokeMethod<bool>('print', {
            'vendorId': vendorId,
            'productId': productId,
            'bytes': Uint8List.fromList(bytes),
          });
        } on PlatformException catch (e) {
          throw StateError('USB printer: ${e.message ?? e.code}');
        }
      });
}

UsbPrinter createUsbPrinter(int vendorId, int productId) => UsbPrinter(vendorId, productId);

/// Printer built into a Sunmi Android POS terminal, driven through Sunmi's
/// printer service with the same ESC/POS bytes.
class BuiltinPrinter implements PrinterAdapter {
  @override
  String get name => 'Built-in printer';

  @override
  Future<void> send(List<int> bytes) => _serialised('builtin', () async {
        if (!Platform.isAndroid) {
          throw const BluetoothUnsupportedPlatform();
        }
        // rebindPrinter answers false (or never, on non-Sunmi hardware)
        // when there is no printer service; only then is printEscPos safe.
        final bound = await SunmiPrinterPlus()
            .rebindPrinter()
            .timeout(const Duration(seconds: 4), onTimeout: () => false)
            .catchError((Object _) => false);
        if (!bound) {
          throw StateError(
              'No built-in printer found. This option works on Sunmi POS terminals.');
        }
        await SunmiPrinter.printEscPos(bytes);
      });
}

BuiltinPrinter createBuiltinPrinter() => BuiltinPrinter();

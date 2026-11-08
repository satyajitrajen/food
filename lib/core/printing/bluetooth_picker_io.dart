import 'dart:async';
import 'dart:io';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth_picker.dart';
import 'printer_io.dart' show bleClient, usbPrinterChannel;

Future<List<PairedPrinterDevice>> listPairedBluetoothDevicesImpl() async {
  if (!Platform.isAndroid) {
    throw UnsupportedError(
        'Bluetooth printing is only available on Android. Use a network (IP:port) printer on this device.');
  }
  // Reading bonded devices needs BLUETOOTH_CONNECT on Android 12+; older
  // versions carry it in the manifest.
  final status = await Permission.bluetoothConnect.request();
  if (!status.isGranted) {
    throw StateError('Bluetooth permission was not granted.');
  }
  final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
  if (!enabled) {
    final asked = await FlutterBluetoothSerial.instance.requestEnable() ?? false;
    if (!asked) throw StateError('Bluetooth is turned off.');
  }
  final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
  return bonded
      .map((d) => PairedPrinterDevice(
            name: d.name?.isNotEmpty == true ? d.name! : d.address,
            address: d.address,
          ))
      .toList();
}

Future<List<PairedPrinterDevice>> scanBlePrintersImpl(Duration timeout) async {
  if (Platform.isAndroid) {
    // Android 12+ scans with BLUETOOTH_SCAN/CONNECT; older versions need
    // location for BLE scans.
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final scanOk = statuses[Permission.bluetoothScan]!.isGranted ||
        statuses[Permission.locationWhenInUse]!.isGranted;
    if (!scanOk) throw StateError('Bluetooth permission was not granted.');
  }
  final found = <String, PairedPrinterDevice>{};
  final done = Completer<void>();
  final sub = bleClient.scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency).listen(
    (d) {
      if (d.name.trim().isEmpty) return;
      found[d.id] = PairedPrinterDevice(name: d.name, address: d.id);
    },
    onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    },
  );
  try {
    await Future.any([done.future, Future<void>.delayed(timeout)]);
  } catch (e) {
    final raw = '$e';
    if (raw.contains('poweredOff') || raw.contains('disabled')) {
      throw StateError('Bluetooth is turned off.');
    }
    if (raw.contains('unauthorized')) {
      throw StateError('Bluetooth permission was not granted.');
    }
    rethrow;
  } finally {
    await sub.cancel();
  }
  final list = found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  return list;
}

Future<List<PairedPrinterDevice>> listUsbPrintersImpl() async {
  if (!Platform.isAndroid) {
    throw UnsupportedError('USB printing is only available on Android tablets and POS terminals.');
  }
  final raw = await usbPrinterChannel.invokeListMethod<Map>('list') ?? const [];
  return [
    for (final d in raw)
      PairedPrinterDevice(
        name: '${d['name'] ?? 'USB printer'}',
        address: '${d['vendorId']}:${d['productId']}',
      ),
  ];
}

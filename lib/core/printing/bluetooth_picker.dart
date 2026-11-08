import 'bluetooth_picker_stub.dart' if (dart.library.io) 'bluetooth_picker_io.dart' as impl;

/// A Bluetooth printer the phone is already paired with.
class PairedPrinterDevice {
  final String name;
  final String address;
  const PairedPrinterDevice({required this.name, required this.address});
}

/// Lists bonded (paired) Bluetooth devices, requesting the Android 12+
/// BLUETOOTH_CONNECT runtime permission first. Throws [UnsupportedError] on
/// platforms without Bluetooth printing support (web, iOS, desktop).
Future<List<PairedPrinterDevice>> listPairedBluetoothDevices() =>
    impl.listPairedBluetoothDevicesImpl();

/// Scans for nearby Bluetooth LE devices for [timeout] (Android + iOS),
/// requesting scan permissions first. Unnamed devices are skipped: printers
/// advertise a name, and the list would otherwise fill with beacons.
Future<List<PairedPrinterDevice>> scanBlePrinters(
        {Duration timeout = const Duration(seconds: 6)}) =>
    impl.scanBlePrintersImpl(timeout);

/// USB devices on an Android host port that have a bulk-OUT endpoint
/// (printers); address is "vendorId:productId".
Future<List<PairedPrinterDevice>> listUsbPrinters() => impl.listUsbPrintersImpl();

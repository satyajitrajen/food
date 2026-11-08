import 'bluetooth_picker.dart';

Future<List<PairedPrinterDevice>> listPairedBluetoothDevicesImpl() async {
  throw UnsupportedError('Bluetooth printing is only available on Android.');
}

Future<List<PairedPrinterDevice>> scanBlePrintersImpl(Duration timeout) async =>
    throw UnsupportedError('Bluetooth LE printing is not available in the web app.');

Future<List<PairedPrinterDevice>> listUsbPrintersImpl() async =>
    throw UnsupportedError('USB printing is not available in the web app.');

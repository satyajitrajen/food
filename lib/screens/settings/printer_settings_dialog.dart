import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/printing/bluetooth_picker.dart';
import '../../core/printing/printing.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Printer kinds this device can drive, in the order shown.
List<PrinterKind> availablePrinterKinds() => [
      PrinterKind.network,
      if (_isAndroid) PrinterKind.bluetooth,
      if (!kIsWeb) PrinterKind.ble,
      if (_isAndroid) PrinterKind.usb,
      if (_isAndroid) PrinterKind.builtin,
      PrinterKind.system,
    ];

String printerKindName(PrinterKind k) => switch (k) {
      PrinterKind.none => 'Not set',
      PrinterKind.network => 'Wi-Fi / LAN (IP address)',
      PrinterKind.bluetooth => 'Bluetooth (paired)',
      PrinterKind.ble => 'Bluetooth LE',
      PrinterKind.usb => 'USB cable',
      PrinterKind.builtin => 'Built-in (Sunmi POS)',
      PrinterKind.system => 'System print (AirPrint / any printer)',
    };

/// Opens the printer setup dialog for the billing and kitchen printers.
Future<void> showPrinterSettingsDialog(BuildContext context, PosProvider provider) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PrinterSettingsDialog(provider: provider, parent: context),
  );
}

class _PrinterSettingsDialog extends StatefulWidget {
  final PosProvider provider;
  final BuildContext parent;
  const _PrinterSettingsDialog({required this.provider, required this.parent});

  @override
  State<_PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _Slot {
  PrinterKind kind;
  final TextEditingController address;
  int paperMm;
  String? deviceName;
  String? error;
  _Slot(PrinterConfig c)
      : kind = c.kind,
        address = TextEditingController(text: c.address),
        paperMm = c.paperMm;

  PrinterConfig get config => kind == PrinterKind.none
      ? PrinterConfig.none
      : PrinterConfig(kind, address: address.text.trim(), paperMm: paperMm);
}

class _PrinterSettingsDialogState extends State<_PrinterSettingsDialog> {
  late final _Slot _billing;
  late final _Slot _kitchen;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.provider;
    _billing = _Slot(p.billingPrinterConfig);
    // Kitchen shows "Same as billing" unless its own printer is set.
    final kitchenOwn = PrinterConfig.parse(p.isDevicePrinter(kitchen: true)
        ? p.kitchenPrinterConfig.encode()
        : p.settings.kitchenPrinter);
    _kitchen = _Slot(kitchenOwn);
    for (final s in [_billing, _kitchen]) {
      if (s.kind != PrinterKind.none && !availablePrinterKinds().contains(s.kind)) {
        s.error = '${printerKindName(s.kind)} is not available on this device.';
      }
    }
  }

  @override
  void dispose() {
    _billing.address.dispose();
    _kitchen.address.dispose();
    super.dispose();
  }

  String? _validate(_Slot s) {
    final a = s.address.text.trim();
    switch (s.kind) {
      case PrinterKind.none:
      case PrinterKind.builtin:
      case PrinterKind.system:
        return null;
      case PrinterKind.network:
        return RegExp(r'^[A-Za-z0-9.\-]+:\d{2,5}$').hasMatch(a)
            ? null
            : 'Use IP:port, e.g. 192.168.1.50:9100';
      case PrinterKind.bluetooth:
        return RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$').hasMatch(a)
            ? null
            : 'Pick a paired printer';
      case PrinterKind.ble:
        return a.isEmpty ? 'Scan and pick a printer' : null;
      case PrinterKind.usb:
        return RegExp(r'^\d+:\d+$').hasMatch(a) ? null : 'Pick a connected USB printer';
    }
  }

  Future<void> _pick(_Slot s) async {
    setState(() => s.error = null);
    final List<PairedPrinterDevice> devices;
    final String title;
    try {
      switch (s.kind) {
        case PrinterKind.bluetooth:
          title = 'Paired Bluetooth printers';
          devices = await listPairedBluetoothDevices();
          if (devices.isEmpty) {
            throw StateError(
                'No paired devices. Pair the printer in the phone\'s Bluetooth settings first.');
          }
        case PrinterKind.ble:
          title = 'Bluetooth LE printers nearby';
          setState(() => _busy = true);
          devices = await scanBlePrinters();
          if (devices.isEmpty) {
            throw StateError('No printers found. Turn the printer on, keep it close, and scan again.');
          }
        case PrinterKind.usb:
          title = 'USB printers';
          devices = await listUsbPrinters();
          if (devices.isEmpty) {
            throw StateError('No USB printer found. Check the cable (OTG adapter on tablets).');
          }
        default:
          return;
      }
    } on UnsupportedError catch (e) {
      setState(() => s.error = e.message ?? 'Not available on this device.');
      return;
    } catch (e) {
      final raw = '$e';
      setState(() => s.error = raw.startsWith('Bad state: ') ? raw.substring(11) : raw);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final chosen = await showModalBottomSheet<PairedPrinterDevice>(
      context: context,
      builder: (bctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final d in devices)
              ListTile(
                leading: const Icon(Icons.print),
                title: Text(d.name),
                subtitle: Text(d.address),
                onTap: () => Navigator.of(bctx).pop(d),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() {
      s.address.text = chosen.address;
      s.deviceName = chosen.name;
    });
  }

  Widget _slotEditor(String label, _Slot s, {required bool kitchen}) {
    final kinds = [PrinterKind.none, ...availablePrinterKinds()];
    if (!kinds.contains(s.kind)) kinds.add(s.kind);
    final needsPick = s.kind == PrinterKind.bluetooth ||
        s.kind == PrinterKind.ble ||
        s.kind == PrinterKind.usb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        DropdownButtonFormField<PrinterKind>(
          initialValue: s.kind,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Connection'),
          items: [
            for (final k in kinds)
              DropdownMenuItem(
                value: k,
                child: Text(k == PrinterKind.none && kitchen ? 'Same as billing printer' : printerKindName(k)),
              ),
          ],
          onChanged: (k) => setState(() {
            s.kind = k ?? PrinterKind.none;
            s.address.clear();
            s.deviceName = null;
            s.error = null;
          }),
        ),
        if (s.kind == PrinterKind.network) ...[
          const SizedBox(height: 8),
          TextField(
            controller: s.address,
            decoration: InputDecoration(
              labelText: 'Printer IP:port',
              hintText: '192.168.1.50:9100',
              errorText: s.error,
            ),
          ),
        ],
        if (needsPick) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.address.text.isEmpty
                      ? 'No printer selected'
                      : '${s.deviceName ?? 'Selected'} · ${s.address.text}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(s),
                icon: Icon(s.kind == PrinterKind.usb ? Icons.usb : Icons.bluetooth_searching),
                label: Text(s.kind == PrinterKind.ble ? 'Scan' : 'Choose'),
              ),
            ],
          ),
        ],
        if (needsPick || s.kind == PrinterKind.builtin || s.kind == PrinterKind.system)
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(s.error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
        if (s.kind != PrinterKind.none) ...[
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 58, label: Text('58 mm paper')),
              ButtonSegment(value: 80, label: Text('80 mm paper')),
            ],
            selected: {s.paperMm},
            onSelectionChanged: (v) => setState(() => s.paperMm = v.first),
          ),
          if (s.config.isDeviceLocal)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Saved on this device only.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _billing.error = _validate(_billing);
      _kitchen.error = _validate(_kitchen);
    });
    if (_billing.error != null || _kitchen.error != null) return;
    final provider = widget.provider;
    final messenger = ScaffoldMessenger.of(widget.parent);
    final navigator = Navigator.of(context);
    await provider.savePrinters(billing: _billing.config, kitchen: _kitchen.config);
    navigator.pop();
    if (!_billing.config.isConfigured) return;
    // System print opens the OS dialog; a test page there would surprise.
    if (_billing.kind == PrinterKind.system) {
      messenger.showSnackBar(const SnackBar(content: Text('Printers saved.')));
      return;
    }
    final ok = await provider.printTestPage();
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Saved. Test page printed.'
          : 'Saved, but test print failed: ${provider.printerError ?? ''}'),
      backgroundColor: ok ? AppColors.success : AppColors.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Printers'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _slotEditor('Billing printer', _billing, kitchen: false),
              const Divider(height: 28),
              _slotEditor('Kitchen KOT printer', _kitchen, kitchen: true),
              const SizedBox(height: 12),
              const Text(
                'Wi-Fi/LAN printers are shared by every terminal in this outlet. '
                'Bluetooth, USB, built-in and system printers are set per device. '
                'Pair classic Bluetooth printers in the phone\'s settings first; '
                'Bluetooth LE printers just need to be switched on.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save & test print')),
      ],
    );
  }
}

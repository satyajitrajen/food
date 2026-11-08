import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/printing/printing.dart';
import '../../providers/pos_provider.dart';

/// Printer status: shows the configured printer name/connection on the home
/// of the manager area, a reachability test and a sample receipt print.
/// Network (host:port on 9100) and Bluetooth (bt:MAC, Android) printers are
/// both supported.
class PrinterStatusScreen extends StatelessWidget {
  const PrinterStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final adapter = provider.printer;
    final name = adapter?.name ?? 'None';
    final isNull = adapter is NullPrinter || adapter == null;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Printer Status & Test',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isNull ? AppColors.borderLight : AppColors.vegGreen,
                  width: isNull ? 1.2 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isNull ? AppColors.creamSubtle : AppColors.vegGreenBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isNull ? Icons.print_disabled_outlined : Icons.print_outlined,
                      color: isNull ? AppColors.textMuted : AppColors.vegGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNull ? 'No printer configured' : name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(
                          isNull
                              ? 'Set a printer in Settings → Printers'
                              : 'Configured in Settings → Printers · status shown on the dashboard',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
                onPressed: isNull
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await provider.printTestPage();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? 'Test page sent to $name'
                                : (provider.printerError ?? 'Printer not reachable')),
                            backgroundColor: ok ? AppColors.vegGreen : AppColors.nonVegRed,
                          ),
                        );
                      },
                icon: const Icon(Icons.local_printshop_outlined, size: 18),
                label: const Text('Print test page'),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Printer types',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              '• Wi-Fi / LAN: connect the printer to the same network and enter its IP (port 9100). Shared by every terminal in the outlet.\n'
              '• Bluetooth (Android): pair the printer in the phone\'s Bluetooth settings, then choose it.\n'
              '• Bluetooth LE (Android and iPhone): switch the printer on and tap Scan.\n'
              '• USB (Android tablets): plug the printer in (OTG adapter) and choose it.\n'
              '• Built-in: Sunmi POS terminals with a printer inside.\n'
              '• System print: any printer the device can already use (AirPrint, Android print service, A4 office printers).\n'
              'Choose 58 mm or 80 mm to match your paper roll.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

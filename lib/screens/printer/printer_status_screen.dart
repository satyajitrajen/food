import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/printing/printing.dart';
import '../../providers/pos_provider.dart';

/// Printer status: shows the configured printer name/connection on the home
/// of the manager area, a reachability test and a sample receipt print.
/// Network (Wi-Fi/Ethernet, host:port on 9100) printers are supported today;
/// Bluetooth pairing lands with the BT transport.
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
                              ? 'Set a printer in Settings → Billing printer (host:port)'
                              : 'Network printer · status shown on the dashboard',
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
              'Bluetooth printers',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bluetooth thermal printers pair like classic SPP devices and are on the roadmap. '
              'Until then, connect the printer to the same Wi-Fi and use its IP (port 9100) in Settings — '
              'the printer name will then show here and on the dashboard.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

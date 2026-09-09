import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';

class OfflineSyncDialog extends StatelessWidget {
  const OfflineSyncDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const OfflineSyncDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SizedBox(
          width: 540,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: provider.isOfflineMode ? AppColors.saffronAmberBg : AppColors.vegGreenBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          provider.isOfflineMode ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                          color: provider.isOfflineMode ? AppColors.saffronAmber : AppColors.vegGreen,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.isOfflineMode ? 'Offline Mode Active' : 'Cloud Sync Status',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          Text(
                            provider.isOfflineMode
                                ? '${provider.pendingSyncCount} changes saved locally'
                                : 'All orders synchronized',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.creamSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Terminal Status:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          provider.isOfflineMode ? 'Local Cache (SQLite)' : 'Online (Baner POS-01)',
                          style: TextStyle(
                            color: provider.isOfflineMode ? AppColors.saffronAmber : AppColors.vegGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20, color: AppColors.borderLight),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pending Sync Queues:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text('${provider.pendingSyncCount} Orders', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                    const Divider(height: 20, color: AppColors.borderLight),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Simulate Offline Switch:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Switch(
                          value: provider.isOfflineMode,
                          activeThumbColor: AppColors.primaryOrange,
                          onChanged: (_) {
                            provider.toggleOfflineMode();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        provider.triggerSync();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Synced with Cloud Server Successfully!'),
                            backgroundColor: AppColors.vegGreen,
                          ),
                        );
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Retry Sync'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
}
}

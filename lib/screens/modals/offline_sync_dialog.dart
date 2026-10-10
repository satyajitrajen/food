import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';

/// Connection status for this terminal: is the server reachable, when it
/// last saved a change, and recent changes that were not saved. Every change
/// is saved on the server straight away; nothing is kept on the device.
class OfflineSyncDialog extends StatefulWidget {
  const OfflineSyncDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const OfflineSyncDialog(),
    );
  }

  @override
  State<OfflineSyncDialog> createState() => _OfflineSyncDialogState();
}

class _OfflineSyncDialogState extends State<OfflineSyncDialog> {
  bool _syncing = false;

  Future<void> _sync(PosProvider provider) async {
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await provider.triggerSync();
    if (!mounted) return;
    setState(() => _syncing = false);
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Connected. Data refreshed from the server.' : 'Server not reachable. Nothing can be saved until it is.'),
      backgroundColor: ok ? AppColors.success : AppColors.warning,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final offline = provider.isOfflineMode;
    final pending = provider.pendingSyncCount;
    final rejections = provider.syncRejections;
    final lastSync = provider.lastSyncAt;

    final String headline;
    final Color tone;
    final IconData icon;
    if (offline) {
      headline = 'No connection';
      tone = AppColors.warning;
      icon = Icons.cloud_off_outlined;
    } else if (pending > 0) {
      headline = 'Saving…';
      tone = AppColors.warning;
      icon = Icons.cloud_sync_outlined;
    } else {
      headline = 'Connected';
      tone = AppColors.success;
      icon = Icons.cloud_done_outlined;
    }

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
      title: Row(
        children: [
          Icon(icon, color: tone),
          const SizedBox(width: 10),
          Expanded(child: Text(headline)),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Server', offline ? 'Not reachable' : 'Connected'),
              _row('Live updates', provider.realtimeConnected ? 'On' : 'Off'),
              _row('Last saved', lastSync == null ? 'Not yet' : formatDateTime(lastSync)),
              if (offline) ...[
                const SizedBox(height: 12),
                _notice(
                  'Nothing can be saved until the server is reachable. Changes '
                  'made just before the connection dropped were not saved; the '
                  'screen shows the server data again once you are back online.',
                  AppColors.warningBg,
                ),
              ],
              if (rejections.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Not saved',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    TextButton(
                      onPressed: provider.clearSyncRejections,
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                for (final r in rejections.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${formatTime(r.at)} · ${_opLabel(r.opType)}: ${r.message}',
                      style: const TextStyle(fontSize: 12, color: AppColors.danger),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: _syncing ? null : () => _sync(provider),
          icon: _syncing
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync, size: 18),
          label: Text(_syncing ? 'Checking…' : 'Refresh'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _notice(String text, Color bg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );

  static String _opLabel(String type) {
    const labels = {
      'order.create': 'New order',
      'order.add_item': 'Add item',
      'order.pay': 'Payment',
      'order.refund': 'Refund',
      'order.patch': 'Order update',
      'kot.fire': 'KOT',
      'shift.open': 'Open shift',
      'shift.close': 'Close shift',
      'expense.create': 'Expense',
      'settings.update': 'Settings',
    };
    return labels[type] ?? type;
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';

/// Real sync status for this terminal: connectivity, queued writes, the last
/// successful sync, why the queue is parked, and writes the server refused.
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
      content: Text(ok
          ? 'All changes are synced'
          : provider.isOfflineMode
              ? 'Server not reachable. Changes stay saved on this device.'
              : '${provider.pendingSyncCount} change(s) still waiting to sync'),
      backgroundColor: ok ? AppColors.success : AppColors.warning,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final offline = provider.isOfflineMode;
    final pending = provider.pendingSyncCount;
    final blocked = provider.syncBlockedReason;
    final rejections = provider.syncRejections;
    final lastSync = provider.lastSyncAt;

    final String headline;
    final Color tone;
    final IconData icon;
    if (offline) {
      headline = 'Offline';
      tone = AppColors.warning;
      icon = Icons.cloud_off_outlined;
    } else if (blocked != null) {
      headline = 'Sync paused';
      tone = AppColors.danger;
      icon = Icons.sync_problem_outlined;
    } else if (pending > 0) {
      headline = 'Syncing…';
      tone = AppColors.warning;
      icon = Icons.cloud_sync_outlined;
    } else {
      headline = 'All changes synced';
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
              _row('Changes waiting to sync', '$pending'),
              _row('Last synced', lastSync == null ? 'Not yet' : formatDateTime(lastSync)),
              if (blocked != null) ...[
                const SizedBox(height: 12),
                _notice(
                  'Sync is paused: $blocked\nNothing is lost. If your session or '
                  'subscription expired, sign in again or renew, then tap Sync now.',
                  AppColors.dangerBg,
                ),
              ],
              if (offline && pending > 0) ...[
                const SizedBox(height: 12),
                _notice(
                  'Your sales are saved on this device and will upload '
                  'automatically when the connection returns.',
                  AppColors.warningBg,
                ),
              ],
              if (rejections.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Refused by the server',
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
          label: Text(_syncing ? 'Syncing…' : 'Sync now'),
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

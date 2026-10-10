import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../models/table_model.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/dialog_controller_scope.dart';
import '../../widgets/table_status_style.dart';

/// Every action for one table in one place: status (reserve / cleaning /
/// available), and for managers edit, move to another section and delete.
/// Actions that would break a running order are disabled with the reason.
Future<void> showTableActions(BuildContext context, RestaurantTable table) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TableActionsSheet(tableId: table.id, messengerContext: context),
  );
}

class _TableActionsSheet extends StatelessWidget {
  final String tableId;

  /// Context of the screen that opened the sheet (for snackbars/dialogs that
  /// outlive the sheet).
  final BuildContext messengerContext;

  const _TableActionsSheet({required this.tableId, required this.messengerContext});

  void _report(String? error, String okText) {
    if (!messengerContext.mounted) return;
    ScaffoldMessenger.of(messengerContext).showSnackBar(SnackBar(
      content: Text(error ?? okText),
      backgroundColor: error == null ? AppColors.success : AppColors.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final table = provider.tables.where((t) => t.id == tableId).firstOrNull;
    if (table == null) return const SizedBox(height: 120, child: Center(child: Text('Table removed')));
    final style = TableStatusStyle.of(table.status);
    final busy = provider.tableIsBusy(table);
    final canManage = provider.canManage;
    final sections = provider.diningSections.where((s) => s != table.floor).toList();

    Widget statusAction(TableStatus status, String label) {
      final s = TableStatusStyle.of(status);
      return ListTile(
        leading: Icon(s.icon, color: s.color),
        title: Text(label),
        enabled: !busy && table.status != status,
        onTap: () {
          Navigator.of(context).pop();
          _report(provider.changeTableStatus(table.id, status), 'Table ${table.tableNumber}: ${s.label}');
        },
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: TableStatusIcon(status: table.status, size: 22),
              title: Text('Table ${table.tableNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              subtitle: Text([
                table.floor,
                '${table.seats} seats',
                style.label,
                if (table.currentOrderAmount > 0) formatInr(table.currentOrderAmount),
              ].join(' · ')),
            ),
            if (busy)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'This table has a running order. Settle or move the order before changing its status, editing or deleting it.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            const Divider(),
            statusAction(TableStatus.reserved, 'Mark reserved'),
            statusAction(TableStatus.cleaning, 'Mark cleaning'),
            statusAction(TableStatus.available, 'Mark available'),
            if (canManage) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit table'),
                subtitle: const Text('Number, seats and section'),
                onTap: () {
                  Navigator.of(context).pop();
                  _editTable(messengerContext, provider, table);
                },
              ),
              if (sections.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('Move to section'),
                  children: [
                    for (final s in sections)
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 72, right: 16),
                        title: Text(s),
                        onTap: () {
                          Navigator.of(context).pop();
                          provider.updateTableSection(table.id, s);
                          _report(null, 'Table ${table.tableNumber} moved to $s');
                        },
                      ),
                  ],
                ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: busy ? null : AppColors.danger),
                title: Text('Delete table',
                    style: TextStyle(color: busy ? null : AppColors.danger, fontWeight: FontWeight.w700)),
                enabled: !busy,
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await showConfirmDialog(
                    messengerContext,
                    title: 'Delete table ${table.tableNumber}?',
                    message: 'It is removed from the floor plan. Past bills keep their table number.',
                    confirmLabel: 'Delete table',
                  );
                  if (!ok) return;
                  _report(provider.deleteTable(table.id), 'Table ${table.tableNumber} deleted');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _editTable(BuildContext context, PosProvider provider, RestaurantTable table) {
    final numC = TextEditingController(text: table.tableNumber);
    final seatsC = TextEditingController(text: '${table.seats}');
    final sections = provider.diningSections;
    var section = sections.contains(table.floor) ? table.floor : (sections.isNotEmpty ? sections.first : table.floor);
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => DialogControllerScope(
        controllers: [numC, seatsC],
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Edit table ${table.tableNumber}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numC,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Table number'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: seatsC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Seats'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: sections.contains(section) ? section : null,
                  decoration: const InputDecoration(labelText: 'Section'),
                  items: [for (final s in sections) DropdownMenuItem(value: s, child: Text(s))],
                  onChanged: (v) => setLocal(() => section = v ?? section),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: AppColors.danger)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final result = provider.editTable(
                  table.id,
                  tableNumber: numC.text,
                  seats: int.tryParse(seatsC.text.trim()) ?? 0,
                  section: section,
                );
                if (result != null) {
                  setLocal(() => error = result);
                  return;
                }
                Navigator.of(ctx).pop();
                _report(null, 'Table saved');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

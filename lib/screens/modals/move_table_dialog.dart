import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/table_model.dart';
import '../../widgets/confirm_dialog.dart';

class MoveTableDialog extends StatefulWidget {
  final RestaurantTable fromTable;

  const MoveTableDialog({super.key, required this.fromTable});

  static void show(BuildContext context, RestaurantTable fromTable) {
    showDialog(
      context: context,
      builder: (ctx) => MoveTableDialog(fromTable: fromTable),
    );
  }

  @override
  State<MoveTableDialog> createState() => _MoveTableDialogState();
}

class _MoveTableDialogState extends State<MoveTableDialog> {
  RestaurantTable? _targetTable;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final availableTables = provider.tables
        .where((t) => t.status == TableStatus.available && t.id != widget.fromTable.id)
        .toList();
    // Friendly order reference instead of the raw internal id.
    final activeOrderId = widget.fromTable.activeOrderId;
    final orderRef = activeOrderId == null
        ? widget.fromTable.tableNumber
        : provider.orders
                .where((o) => o.id == activeOrderId)
                .firstOrNull
                ?.orderNumber ??
            widget.fromTable.tableNumber;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SizedBox(
          width: 540,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Move Table ${widget.fromTable.tableNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Transfer running order $orderRef to an available destination table.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              const Text('Select Destination Table:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 10),
              if (availableTables.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: const Text('No available tables on floor!'),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: availableTables.map((tbl) {
                        final isSelected = _targetTable?.id == tbl.id;
                        return ChoiceChip(
                          label: Text('${tbl.tableNumber} (${tbl.seats} Seats)'),
                          selected: isSelected,
                          selectedColor: AppColors.primaryGreen,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textDark,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (_) => setState(() => _targetTable = tbl),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _targetTable == null
                      ? null
                      : () async {
                          final ok = await showConfirmDialog(
                            context,
                            title: 'Move table?',
                            message:
                                'Move order from ${widget.fromTable.tableNumber} to ${_targetTable!.tableNumber}?',
                            confirmLabel:
                                'Move to ${_targetTable!.tableNumber}',
                            isDanger: false,
                          );
                          if (!ok || !context.mounted) return;
                          provider.moveTable(widget.fromTable.id, _targetTable!.id);
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ Moved ${widget.fromTable.tableNumber} to ${_targetTable!.tableNumber}'),
                              backgroundColor: AppColors.vegGreen,
                            ),
                          );
                        },
                  child: Text('Move to ${_targetTable?.tableNumber ?? "Destination"}'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/table_model.dart';

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

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SizedBox(
          width: 540,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Move Table ${widget.fromTable.tableNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Transfer running order #${widget.fromTable.activeOrderId ?? ""} to an available destination table.',
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
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: availableTables.map((tbl) {
                    final isSelected = _targetTable?.id == tbl.id;
                    return ChoiceChip(
                      label: Text('${tbl.tableNumber} (${tbl.seats} Seats)'),
                      selected: isSelected,
                      selectedColor: AppColors.primaryOrange,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => setState(() => _targetTable = tbl),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _targetTable == null
                      ? null
                      : () {
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

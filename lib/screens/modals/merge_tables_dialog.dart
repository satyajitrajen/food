import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/table_model.dart';

class MergeTablesDialog extends StatefulWidget {
  final RestaurantTable primaryTable;

  const MergeTablesDialog({super.key, required this.primaryTable});

  static void show(BuildContext context, RestaurantTable primaryTable) {
    showDialog(
      context: context,
      builder: (ctx) => MergeTablesDialog(primaryTable: primaryTable),
    );
  }

  @override
  State<MergeTablesDialog> createState() => _MergeTablesDialogState();
}

class _MergeTablesDialogState extends State<MergeTablesDialog> {
  final Set<String> _selectedSecondaryIds = {};

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final tables = provider.tables
        .where((t) => t.id != widget.primaryTable.id)
        // Can't steal a table already merged to a different primary.
        .where((t) => t.mergedWithTableId == null || t.mergedWithTableId == widget.primaryTable.id)
        .toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: SizedBox(
          width: 560,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Merge Tables with ${widget.primaryTable.tableNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Select additional tables to link together into this primary bill.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var t in tables) ...[
                        CheckboxListTile(
                          value: _selectedSecondaryIds.contains(t.id) || t.mergedWithTableId == widget.primaryTable.id,
                          activeColor: AppColors.primaryOrange,
                          title: Text('${t.tableNumber} (${t.seats} Seats) — ${t.floor}'),
                          subtitle: Text('Status: ${t.statusLabel}'),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedSecondaryIds.add(t.id);
                              } else {
                                _selectedSecondaryIds.remove(t.id);
                                if (t.mergedWithTableId == widget.primaryTable.id) {
                                  provider.unmergeTable(t.id);
                                }
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedSecondaryIds.isEmpty
                          ? null
                          : () {
                              for (var id in _selectedSecondaryIds) {
                                provider.mergeTables(widget.primaryTable.id, id);
                              }
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ Merged ${_selectedSecondaryIds.length} tables with ${widget.primaryTable.tableNumber}'),
                                  backgroundColor: AppColors.vegGreen,
                                ),
                              );
                            },
                      child: const Text('Merge Tables'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

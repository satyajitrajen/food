import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/table_model.dart';
import '../../widgets/confirm_dialog.dart';
import '../modals/guest_details_dialog.dart';
import '../pos_menu/pos_menu_screen.dart';
import '../running_orders/running_order_detail_screen.dart';
import '../../widgets/empty_state.dart';
import '../settings/dining_sections_screen.dart';
import 'table_actions_sheet.dart';
import '../../widgets/table_status_style.dart';
import '../../core/format.dart';

class TableSelectionScreen extends StatelessWidget {
  final bool isSelectingForOrder;

  const TableSelectionScreen({super.key, this.isSelectingForOrder = false});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    // Section chips come from managed dining sections (Garden/AC Dining/Bar),
    // with 'All' as the default view.
    final sections = provider.diningSections;
    final floors = ['All', ...sections];

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text(
          'Floor Tables',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (provider.canManage)
            IconButton(
              tooltip: 'Manage sections & tables',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DiningSectionsScreen())),
            ),
          Container(
            margin: const EdgeInsets.fromLTRB(4, 8, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.creamSubtle,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.table_bar_outlined,
                  size: 16,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  '${provider.tables.where((t) => t.status == TableStatus.available).length} Free / ${provider.tables.length} Total',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Section + status filters: two dropdowns in one row.
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: floors.contains(provider.selectedFloor) ? provider.selectedFloor : 'All',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Section',
                        isDense: true,
                        prefixIcon: Icon(Icons.layers_outlined, size: 20),
                      ),
                      items: [
                        for (final f in floors)
                          DropdownMenuItem(
                            value: f,
                            child: Text(f == 'All' ? 'All sections' : f, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (f) {
                        if (f != null) provider.setFloor(f);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: provider.selectedTableStatus,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Status',
                        isDense: true,
                        prefixIcon: Icon(
                          TableStatusStyle.fromLabel(provider.selectedTableStatus) == null
                              ? Icons.filter_list
                              : TableStatusStyle.of(TableStatusStyle.fromLabel(provider.selectedTableStatus)!).icon,
                          size: 20,
                          color: TableStatusStyle.fromLabel(provider.selectedTableStatus) == null
                              ? null
                              : TableStatusStyle.of(TableStatusStyle.fromLabel(provider.selectedTableStatus)!).color,
                        ),
                      ),
                      // The closed field shows just the name; the menu adds
                      // each status's icon and how many tables are in it.
                      selectedItemBuilder: (_) => [
                        for (final f in PosProvider.tableStatusFilters)
                          Text(f == 'All' ? 'All statuses' : f, overflow: TextOverflow.ellipsis),
                      ],
                      items: [
                        for (final f in PosProvider.tableStatusFilters)
                          DropdownMenuItem(
                            value: f,
                            child: Builder(builder: (_) {
                              final status = TableStatusStyle.fromLabel(f);
                              final count = status == null
                                  ? provider.tables.length
                                  : provider.tables.where((t) => t.status == status).length;
                              return Row(
                                children: [
                                  if (status != null) ...[
                                    Icon(TableStatusStyle.of(status).icon,
                                        size: 18, color: TableStatusStyle.of(status).color),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(f == 'All' ? 'All statuses' : f, overflow: TextOverflow.ellipsis),
                                  ),
                                  Text('$count',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800, color: AppColors.textMuted)),
                                ],
                              );
                            }),
                          ),
                      ],
                      onChanged: (f) {
                        if (f != null) provider.setTableStatus(f);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),
            // Tables Grid
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Determine column count based on available screen width
                  final crossAxisCount = constraints.maxWidth > 900
                      ? 6
                      : constraints.maxWidth > 600
                          ? 4
                          : 3;

                  final tables = provider.filteredTables;
                  if (tables.isEmpty) {
                    return EmptyState(
                      icon: Icons.table_restaurant_outlined,
                      title: provider.tables.isEmpty
                          ? 'No tables yet'
                          : 'No tables match this filter',
                      message: provider.tables.isEmpty
                          ? (provider.canManage
                                ? 'Add tables with the manage button above (Sections & tables).'
                                : 'Ask a manager to add tables. Takeaway orders work from the POS tab.')
                          : null,
                      actionLabel: provider.tables.isEmpty ? 'Refresh' : null,
                      onAction: provider.tables.isEmpty
                          ? provider.triggerSync
                          : null,
                      isError: false,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: provider.triggerSync,
                    child: GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.95,
                      ),
                      itemCount: tables.length,
                      itemBuilder: (context, index) {
                        final table = tables[index];
                        return _buildTableCard(context, table, provider);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCard(
    BuildContext context,
    RestaurantTable table,
    PosProvider provider,
  ) {
    // Guest info lives on the table's running order — surface it on the card.
    final guestOrder = table.activeOrderId == null
        ? null
        : provider.orders.where((o) => o.id == table.activeOrderId).firstOrNull;
    final customerLine = [
      if ((guestOrder?.customerName ?? '').isNotEmpty)
        guestOrder!.customerName!,
      if ((guestOrder?.customerPhone ?? '').isNotEmpty)
        guestOrder!.customerPhone!,
    ].join(' · ');
    final style = TableStatusStyle.of(table.status);
    final busy = table.status == TableStatus.occupied || table.status == TableStatus.billing;
    final elapsed = _elapsedSince(guestOrder?.createdAt);

    return InkWell(
      // Long-press: status, edit, move and delete for this table.
      onLongPress: () => showTableActions(context, table),
      onTap: () async {
        provider.selectTable(table);

        if (table.status == TableStatus.available) {
          if (!provider.canTakeOrders) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Subscription is not active — renew to start new orders. '
                  'Existing bills can still be served and closed.',
                ),
                duration: Duration(seconds: 4),
              ),
            );
            return;
          }
          // Open Guest Details dialog then start POS
          GuestDetailsDialog.show(
            context,
            onStartOrder: () {
              // Picked from the POS: go back to it rather than stacking a
              // second POS screen on top.
              if (isSelectingForOrder && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PosMenuScreen()),
                );
              }
            },
          );
        } else if (table.status == TableStatus.occupied ||
            table.status == TableStatus.billing) {
          if (isSelectingForOrder && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else if (provider.activeOrder != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    RunningOrderDetailScreen(order: provider.activeOrder!),
              ),
            );
          } else {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PosMenuScreen()));
          }
        } else {
          // Reserved or Cleaning - Allow toggle to available via provider
          final ok = await showConfirmDialog(
            context,
            title: 'Mark table available?',
            message:
                'Mark table ${table.tableNumber} as Available? This changes floor status.',
            confirmLabel: 'Mark Available',
            isDanger: false,
          );
          if (!ok || !context.mounted) return;
          provider.markTableAvailable(table);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Table ${table.tableNumber} is now marked Available!',
              ),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: style.background.withValues(alpha: table.status == TableStatus.available ? 0.35 : 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: style.color.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    table.tableNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TableStatusIcon(status: table.status, size: 16),
              ],
            ),
            const Spacer(),
            if (busy) ...[
              Text(
                formatInr(table.currentOrderAmount),
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: style.color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      elapsed,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            Row(
              children: [
                Icon(
                  table.guestCount > 0 ? Icons.people_alt_outlined : Icons.event_seat_outlined,
                  size: 13,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    table.guestCount > 0 ? '${table.guestCount}/${table.seats}' : '${table.seats}',
                    semanticsLabel: table.guestCount > 0
                        ? '${table.guestCount} guests of ${table.seats} seats'
                        : '${table.seats} seats',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (customerLine.isNotEmpty)
              Text(
                customerLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textDark, fontSize: 11, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }

  /// Time since the table's order was opened (ticks with every rebuild,
  /// unlike the server's stored minutes).
  static String _elapsedSince(DateTime? start) {
    if (start == null) return '';
    final m = DateTime.now().difference(start).inMinutes;
    if (m < 1) return 'just now';
    if (m < 60) return '$m min';
    return '${m ~/ 60}h ${m % 60}m';
  }
}

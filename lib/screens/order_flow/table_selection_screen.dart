import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/table_model.dart';
import '../../widgets/custom_badge.dart';
import '../modals/guest_details_dialog.dart';
import '../pos_menu/pos_menu_screen.dart';
import '../running_orders/running_order_detail_screen.dart';

class TableSelectionScreen extends StatelessWidget {
  final bool isSelectingForOrder;

  const TableSelectionScreen({super.key, this.isSelectingForOrder = true});

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
        title: const Text('Floor Tables', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.creamSubtle,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.table_bar_outlined, size: 16, color: AppColors.primaryOrange),
                const SizedBox(width: 6),
                Text(
                  '${provider.tables.where((t) => t.status == TableStatus.available).length} Free / ${provider.tables.length} Total',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
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
            // Floor Tabs
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: floors.map((f) {
                    final isSelected = provider.selectedFloor == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f),
                        selected: isSelected,
                        selectedColor: AppColors.primaryOrange,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        onSelected: (_) => provider.setFloor(f),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),
            // Tables Grid
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Determine column count based on available screen width
                  int crossAxisCount = 2;
                  if (constraints.maxWidth > 900) {
                    crossAxisCount = 4;
                  } else if (constraints.maxWidth > 600) {
                    crossAxisCount = 3;
                  }

                  final tables = provider.filteredTables;

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: constraints.maxWidth > 600 ? 1.3 : 1.18,
                    ),
                    itemCount: tables.length,
                    itemBuilder: (context, index) {
                      final table = tables[index];
                      return _buildTableCard(context, table, provider);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCard(BuildContext context, RestaurantTable table, PosProvider provider) {
    Color borderColor = AppColors.borderLight;
    if (table.status == TableStatus.occupied) borderColor = AppColors.primaryOrange.withValues(alpha: 0.5);
    if (table.status == TableStatus.billing) borderColor = AppColors.saffronAmber;

    return InkWell(
      onTap: () {
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
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PosMenuScreen()),
              );
            },
          );
        } else if (table.status == TableStatus.occupied || table.status == TableStatus.billing) {
          // Open Running Order
          if (provider.activeOrder != null) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RunningOrderDetailScreen(order: provider.activeOrder!)),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PosMenuScreen()),
            );
          }
        } else {
          // Reserved or Cleaning - Allow toggle to available via provider
          provider.markTableAvailable(table);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Table ${table.tableNumber} is now marked Available!')),
          );
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  table.tableNumber,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5),
                ),
                StatusBadge.forTable(table.status),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.event_seat_outlined, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${table.seats} Seats · ${table.floor.split(" ").first}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 8, color: AppColors.borderLight),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: table.currentOrderAmount > 0
                      ? Text(
                          '₹${table.currentOrderAmount.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.primaryOrange),
                          overflow: TextOverflow.ellipsis,
                        )
                      : const Text(
                          'No Bill',
                          style: TextStyle(color: AppColors.textLight, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                const SizedBox(width: 4),
                table.runningMinutes > 0
                    ? Text(
                        '${table.runningMinutes} min',
                        style: const TextStyle(color: AppColors.textLight, fontSize: 11, fontWeight: FontWeight.w600),
                      )
                    : const Text(
                        'Order',
                        style: TextStyle(color: AppColors.vegGreen, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

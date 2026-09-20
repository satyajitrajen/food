import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/app_nav.dart';
import '../../models/order_model.dart';
import '../../models/staff_model.dart';
import '../../models/table_model.dart';
import '../modals/merge_tables_dialog.dart';
import 'running_order_detail_screen.dart';
import 'ready_to_serve_screen.dart';
import '../pos_menu/pos_menu_screen.dart';

class RunningOrdersScreen extends StatefulWidget {
  const RunningOrdersScreen({super.key});

  @override
  State<RunningOrdersScreen> createState() => _RunningOrdersScreenState();
}

class _RunningOrdersScreenState extends State<RunningOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Filters by table number. Orders without a table (counter orders) are
  /// hidden while a query is active.
  List<RestaurantOrder> _applySearch(List<RestaurantOrder> orders) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return orders;
    return orders.where((o) => (o.tableNumber ?? '').toLowerCase().contains(q)).toList();
  }

  RestaurantTable? _tableFor(PosProvider provider, RestaurantOrder order) {
    if (order.tableId == null) return null;
    for (final t in provider.tables) {
      if (t.id == order.tableId) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final isWaiter = provider.currentStaff?.role == StaffRole.waiter;
    final runningOrders = provider.runningOrders;

    final dineInOrders = runningOrders.where((o) => o.orderType == OrderType.dineIn).toList();
    final readyCount = provider.readyToServe.length;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isWaiter ? 'My Orders' : 'Running Orders',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            if (isWaiter && provider.currentStaff != null)
              Text(
                'Waiter: ${provider.currentStaff!.name}',
                style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 12),
              ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (isWaiter)
            IconButton(
              tooltip: 'Ready to Serve',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReadyToServeScreen()),
                );
              },
              icon: Badge(
                isLabelVisible: readyCount > 0,
                label: Text('$readyCount'),
                child: const Icon(Icons.room_service_outlined),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryGreen,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primaryGreen,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: [
            Tab(text: 'All (${runningOrders.length})'),
            Tab(text: 'Dine-In (${dineInOrders.length})'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Search orders by table number
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _query = val),
                decoration: InputDecoration(
                  hintText: 'Search by table number...',
                  prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textLight),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  fillColor: AppColors.creamSubtle,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOrdersList(context, _applySearch(runningOrders), provider),
                  _buildOrdersList(context, _applySearch(dineInOrders), provider),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(BuildContext context, List<RestaurantOrder> orders, PosProvider provider) {
    final isWaiter = provider.currentStaff?.role == StaffRole.waiter;
    final searching = _query.trim().isNotEmpty;
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 52, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(
              searching
                  ? 'No orders match table "${_query.trim()}"'
                  : isWaiter
                      ? 'No active orders assigned to you'
                      : 'No running orders in this queue',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            if (!searching) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  provider.goToDest(isWaiter ? AppDest.tables : AppDest.pos);
                },
                child: const Text('Start New Order'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final tableName = order.tableNumber ?? order.orderTypeLabel;
        final table = _tableFor(provider, order);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              order.orderNumber,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreenLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                tableName,
                                style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w800, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (table != null)
                      IconButton(
                        icon: const Icon(Icons.call_merge, size: 18, color: AppColors.textDark),
                        tooltip: 'Merge Tables',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => MergeTablesDialog.show(context, table),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.saffronAmberBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        order.statusLabel,
                        style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${order.totalItemCount} Items · ₹${order.grandTotal.toStringAsFixed(0)} · Waiter: ${order.waiterName ?? "Staff"}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Divider(height: 20, color: AppColors.borderLight),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          provider.openRunningOrder(order);
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PosMenuScreen()),
                          );
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Items'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => RunningOrderDetailScreen(order: order)),
                          );
                        },
                        child: const Text('Open Order'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

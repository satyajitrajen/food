import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/app_nav.dart';
import '../../models/order_model.dart';
import '../../models/staff_model.dart';
import 'running_order_detail_screen.dart';
import '../pos_menu/pos_menu_screen.dart';

class RunningOrdersScreen extends StatefulWidget {
  const RunningOrdersScreen({super.key});

  @override
  State<RunningOrdersScreen> createState() => _RunningOrdersScreenState();
}

class _RunningOrdersScreenState extends State<RunningOrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final isWaiter = provider.currentStaff?.role == StaffRole.waiter;
    final runningOrders = provider.runningOrders;

    final dineInOrders = runningOrders.where((o) => o.orderType == OrderType.dineIn).toList();
    final takeawayOrders = runningOrders.where((o) => o.orderType == OrderType.takeaway).toList();
    final deliveryOrders = runningOrders.where((o) => o.orderType == OrderType.delivery).toList();

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
            Tab(text: 'Takeaway (${takeawayOrders.length})'),
            Tab(text: 'Delivery (${deliveryOrders.length})'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildOrdersList(context, runningOrders, provider),
            _buildOrdersList(context, dineInOrders, provider),
            _buildOrdersList(context, takeawayOrders, provider),
            _buildOrdersList(context, deliveryOrders, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(BuildContext context, List<RestaurantOrder> orders, PosProvider provider) {
    final isWaiter = provider.currentStaff?.role == StaffRole.waiter;
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 52, color: AppColors.textLight),
            const SizedBox(height: 12),
            Text(
              isWaiter
                  ? 'No active orders assigned to you'
                  : 'No running orders in this queue',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                provider.goToDest(isWaiter ? AppDest.tables : AppDest.pos);
              },
              child: const Text('Start New Order'),
            ),
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
                        label: const Text('+ Add Items'),
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
                        child: const Text('Open Order →'),
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

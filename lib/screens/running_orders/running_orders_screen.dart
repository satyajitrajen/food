import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/app_nav.dart';
import '../../models/order_model.dart';
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
    final runningOrders = provider.runningOrders;

    final dineInOrders = runningOrders.where((o) => o.orderType == OrderType.dineIn).toList();
    final takeawayOrders = runningOrders.where((o) => o.orderType == OrderType.takeaway).toList();
    final deliveryOrders = runningOrders.where((o) => o.orderType == OrderType.delivery).toList();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Running Orders', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryOrange,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primaryOrange,
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
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 52, color: AppColors.textLight),
            const SizedBox(height: 12),
            const Text('No running orders in this queue', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                provider.goToDest(AppDest.pos); // Go to POS
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          order.orderNumber,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryOrangeLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tableName,
                            style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ),
                      ],
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

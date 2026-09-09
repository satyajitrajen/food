import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/app_nav.dart';
import '../../models/table_model.dart';
import '../../models/kot_model.dart';
import '../../widgets/stat_kpi_card.dart';
import '../order_flow/select_order_type_dialog.dart';
import '../order_flow/table_selection_screen.dart';
import '../kitchen/kitchen_board_screen.dart';
import '../transactions/transactions_screen.dart';
import '../expenses/expense_screen.dart';
import '../pos_menu/pos_menu_screen.dart';
import '../running_orders/running_order_detail_screen.dart';
import '../modals/offline_sync_dialog.dart';

class PosDashboardScreen extends StatelessWidget {
  const PosDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final shift = provider.currentShift;

    // Financial Metrics. Server truth (outlet-wide, all terminals) when the
    // dashboard report is available; local computation is the offline fallback.
    final rep = provider.serverDashboard;
    final todaySales = rep?.sales ?? (shift?.totalSales ?? 0.0);
    final orderCount = rep?.orderCount ?? provider.completedTransactions.length;
    final aov = rep?.aov ?? (orderCount > 0 ? (todaySales / orderCount) : 0.0);
    final todayExp = rep?.expenses ?? provider.todayExpenses;
    final cashInDrawer = rep?.cashDrawer ?? shift?.expectedCash ?? 0.0;
    final pendingKOTs = rep?.pendingKots ??
        provider.kots
            .where((k) => k.status != KOTStatus.served && k.status != KOTStatus.cancelled)
            .length;

    // Table Counts
    final freeTables = provider.tables.where((t) => t.status == TableStatus.available).length;
    final occupiedTables = provider.tables.where((t) => t.status == TableStatus.occupied).length;
    final billingTables = provider.tables.where((t) => t.status == TableStatus.billing).length;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryOrange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.restaurant, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.currentOutlet.name,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                Text(
                  'Terminal ${provider.currentOutlet.terminal} · Cashier: ${provider.currentStaff?.name ?? "Staff"}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              provider.isOfflineMode ? Icons.cloud_off : Icons.cloud_done_outlined,
              color: provider.isOfflineMode ? AppColors.saffronAmber : AppColors.vegGreen,
            ),
            tooltip: 'Sync & Offline Status',
            onPressed: () => OfflineSyncDialog.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Grid (Sales, Orders, AOV, Expenses, Cash Drawer, Pending KOT)
            LayoutBuilder(
              builder: (context, constraints) {
                int cols = constraints.maxWidth > 900 ? 6 : (constraints.maxWidth > 600 ? 3 : 2);
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: constraints.maxWidth > 900 ? 1.4 : (constraints.maxWidth > 600 ? 1.3 : 1.15),
                  children: [
                    StatKpiCard(
                      title: "Today's Sales",
                      value: '₹${todaySales.toStringAsFixed(0)}',
                      icon: Icons.payments_outlined,
                      iconColor: AppColors.primaryOrange,
                      iconBgColor: AppColors.primaryOrangeLight,
                    ),
                    StatKpiCard(
                      title: 'Total Orders',
                      value: '$orderCount',
                      icon: Icons.receipt_long_outlined,
                      iconColor: AppColors.infoBlue,
                      iconBgColor: AppColors.infoBlueBg,
                    ),
                    StatKpiCard(
                      title: 'Avg Order (AOV)',
                      value: '₹${aov.toStringAsFixed(0)}',
                      icon: Icons.trending_up,
                      iconColor: AppColors.vegGreen,
                      iconBgColor: AppColors.vegGreenBg,
                    ),
                    StatKpiCard(
                      title: 'Today Expenses',
                      value: '₹${todayExp.toStringAsFixed(0)}',
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: AppColors.nonVegRed,
                      iconBgColor: AppColors.nonVegRedBg,
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExpenseScreen()));
                      },
                    ),
                    StatKpiCard(
                      title: 'Cash in Drawer',
                      value: '₹${cashInDrawer.toStringAsFixed(0)}',
                      icon: Icons.point_of_sale,
                      iconColor: AppColors.saffronAmber,
                      iconBgColor: AppColors.saffronAmberBg,
                    ),
                    StatKpiCard(
                      title: 'Pending KOTs',
                      value: '$pendingKOTs',
                      icon: Icons.soup_kitchen_outlined,
                      iconColor: AppColors.primaryOrange,
                      iconBgColor: AppColors.primaryOrangeLight,
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KitchenBoardScreen()));
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Floor Tables Snapshot Strip
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Table Floor Status', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      TextButton(
                        onPressed: () {
                          provider.goToDest(AppDest.tables); // Switch to Tables tab
                        },
                        child: const Text('View All Tables →', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildFloorBadge('Available', '$freeTables Free', AppColors.vegGreen, AppColors.vegGreenBg),
                      const SizedBox(width: 8),
                      _buildFloorBadge('Occupied', '$occupiedTables Running', AppColors.primaryOrange, AppColors.primaryOrangeLight),
                      const SizedBox(width: 8),
                      _buildFloorBadge('Billing', '$billingTables Invoiced', AppColors.saffronAmber, AppColors.saffronAmberBg),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Quick Actions Bar
            const Text('Quick Operational Actions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickActionBtn(
                    title: '+ New Order',
                    icon: Icons.add_circle,
                    color: AppColors.primaryOrange,
                    onTap: () {
                      SelectOrderTypeDialog.show(
                        context,
                        onSelectType: (type) {
                          if (type.name == 'dineIn') {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const TableSelectionScreen()),
                            );
                          } else {
                            provider.startNewOrder(type);
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PosMenuScreen()),
                            );
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildQuickActionBtn(
                    title: 'Floor Tables',
                    icon: Icons.table_restaurant,
                    color: AppColors.textDark,
                    onTap: () => provider.goToDest(AppDest.tables),
                  ),
                  const SizedBox(width: 10),
                  _buildQuickActionBtn(
                    title: 'Kitchen KOT',
                    icon: Icons.soup_kitchen,
                    color: AppColors.infoBlue,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KitchenBoardScreen()));
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildQuickActionBtn(
                    title: 'Transactions',
                    icon: Icons.receipt_long,
                    color: AppColors.vegGreen,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TransactionsScreen()));
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildQuickActionBtn(
                    title: 'Add Expense',
                    icon: Icons.money_off,
                    color: AppColors.nonVegRed,
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExpenseScreen()));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Recent Orders List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent Orders & Bills', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                TextButton(
                  onPressed: () => provider.goToDest(AppDest.runningOrders), // Orders tab
                  child: const Text('See All', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: provider.orders.take(4).length,
              itemBuilder: (context, index) {
                final order = provider.orders[index];
                final timeStr = DateFormat('hh:mm a').format(order.createdAt);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.creamSubtle,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.fastfood, color: AppColors.primaryOrange, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${order.orderNumber} · ${order.tableNumber != null ? "Table ${order.tableNumber}" : order.orderTypeLabel}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${order.totalItemCount} Items · $timeStr · ${order.statusLabel}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${order.grandTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textDark),
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => RunningOrderDetailScreen(order: order)),
                              );
                            },
                            child: const Text(
                              'Details →',
                              style: TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloorBadge(String label, String value, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionBtn({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

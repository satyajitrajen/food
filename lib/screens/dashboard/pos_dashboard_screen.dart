import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/app_nav.dart';
import '../../widgets/table_status_style.dart';
import '../../models/table_model.dart';
import '../../models/kot_model.dart';
import '../../widgets/stat_kpi_card.dart';
import '../running_orders/running_order_detail_screen.dart';
import '../modals/offline_sync_dialog.dart';
import '../../core/format.dart';

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
    // The open shift on this terminal is live; the server snapshot can be
    // older than the latest float, sale or cash move.
    final cashInDrawer = shift?.expectedCash ?? rep?.cashDrawer ?? 0.0;
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
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.restaurant, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.currentOutlet.name,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      if (provider.currentOutlet.terminal.isNotEmpty) provider.currentOutlet.terminal,
                      if (provider.currentStaff != null) provider.currentStaff!.name,
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: provider.pendingSyncCount > 0,
              label: Text('${provider.pendingSyncCount}'),
              child: Icon(
                provider.isOfflineMode
                    ? Icons.cloud_off
                    : provider.syncRejections.isNotEmpty
                        ? Icons.sync_problem_outlined
                        : Icons.cloud_done_outlined,
                color: provider.isOfflineMode || provider.syncRejections.isNotEmpty
                    ? AppColors.warning
                    : AppColors.success,
              ),
            ),
            tooltip: 'Connection',
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
                  // Compact tiles so the floor status stays above the fold.
                  childAspectRatio: constraints.maxWidth > 900 ? 1.9 : (constraints.maxWidth > 600 ? 1.9 : 1.75),
                  children: [
                    StatKpiCard(
                      title: 'Sales today',
                      value: formatInr(todaySales),
                      icon: Icons.payments_outlined,
                      iconColor: AppColors.primaryGreen,
                      iconBgColor: AppColors.primaryGreenLight,
                    ),
                    StatKpiCard(
                      title: 'Orders',
                      value: '$orderCount',
                      icon: Icons.receipt_long_outlined,
                      iconColor: AppColors.infoBlue,
                      iconBgColor: AppColors.infoBlueBg,
                    ),
                    StatKpiCard(
                      title: 'Avg order',
                      value: formatInr(aov),
                      icon: Icons.trending_up,
                      iconColor: AppColors.vegGreen,
                      iconBgColor: AppColors.vegGreenBg,
                    ),
                    StatKpiCard(
                      title: 'Expenses',
                      value: formatInr(todayExp),
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: AppColors.nonVegRed,
                      iconBgColor: AppColors.nonVegRedBg,
                      onTap: () {
                        provider.goToDest(AppDest.expenses);
                      },
                    ),
                    StatKpiCard(
                      title: 'Cash in drawer',
                      value: formatInr(cashInDrawer),
                      icon: Icons.point_of_sale,
                      iconColor: AppColors.saffronAmber,
                      iconBgColor: AppColors.saffronAmberBg,
                    ),
                    StatKpiCard(
                      title: 'Open KOTs',
                      value: '$pendingKOTs',
                      icon: Icons.soup_kitchen_outlined,
                      iconColor: AppColors.primaryGreen,
                      iconBgColor: AppColors.primaryGreenLight,
                      onTap: () {
                        provider.goToDest(AppDest.kitchen);
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
                      _buildFloorBadge(TableStatus.available, freeTables),
                      const SizedBox(width: 8),
                      _buildFloorBadge(TableStatus.occupied, occupiedTables),
                      const SizedBox(width: 8),
                      _buildFloorBadge(TableStatus.billing, billingTables),
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
                    title: 'New order',
                    icon: Icons.add_circle,
                    color: AppColors.primaryGreen,
                    onTap: () {
                      provider.goToDest(AppDest.tables);
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
                      provider.goToDest(AppDest.kitchen);
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildQuickActionBtn(
                    title: 'Transactions',
                    icon: Icons.receipt_long,
                    color: AppColors.vegGreen,
                    onTap: () {
                      provider.goToDest(AppDest.transactions);
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildQuickActionBtn(
                    title: 'Add Expense',
                    icon: Icons.money_off,
                    color: AppColors.nonVegRed,
                    onTap: () {
                      provider.goToDest(AppDest.expenses);
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
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.creamSubtle,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.fastfood, color: AppColors.primaryGreen, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${order.orderNumber} · ${order.tableNumber != null ? "Table ${order.tableNumber}" : order.orderTypeLabel}',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${plural(order.totalItemCount, 'item')} · $timeStr · ${order.statusLabel}',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatInr(order.grandTotal),
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
                              style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w700, fontSize: 12),
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

  /// Same icon + colour per status as the Tables screen; the word stays in
  /// the tooltip / screen-reader label.
  Widget _buildFloorBadge(TableStatus status, int count) {
    final style = TableStatusStyle.of(status);
    return Expanded(
      child: Tooltip(
        message: style.label,
        child: Semantics(
          label: '$count ${style.label}',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(style.icon, color: style.color, size: 20),
                const SizedBox(width: 8),
                Text('$count', style: TextStyle(color: style.color, fontWeight: FontWeight.w900, fontSize: 18)),
              ],
            ),
          ),
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

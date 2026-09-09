import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/order_model.dart';
import '../../models/menu_model.dart';

class CategorySales {
  final String name;
  final double revenue;
  final int itemQty;
  CategorySales(this.name, this.revenue, this.itemQty);
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  // All figures derive from real provider data — no fabricated fallbacks.
  // Sales scope = current shift (matches dashboard + Z-report).

  static Map<OrderType, ({double amount, int count})> _salesByType(
      List<RestaurantOrder> completed) {
    final map = <OrderType, ({double amount, int count})>{};
    for (final o in completed) {
      final cur = map[o.orderType] ?? (amount: 0.0, count: 0);
      map[o.orderType] = (amount: cur.amount + o.grandTotal, count: cur.count + 1);
    }
    return map;
  }

  static Map<String, double> _salesByTender(List<RestaurantOrder> completed) {
    final map = <String, double>{};
    for (final o in completed) {
      final key = o.paymentMethod ?? 'Other';
      map[key] = (map[key] ?? 0.0) + o.grandTotal;
    }
    return map;
  }

  static List<CategorySales> _salesByCategory(
      List<RestaurantOrder> completed, List<MenuItem> menu) {
    final revenue = <String, double>{};
    final qty = <String, int>{};
    final menuById = {for (final m in menu) m.id: m};
    for (final o in completed) {
      for (final item in o.items) {
        if (item.isCancelled) continue;
        final cat = menuById[item.menuItem.id]?.category ?? 'Other';
        revenue[cat] = (revenue[cat] ?? 0.0) + item.totalPrice;
        qty[cat] = (qty[cat] ?? 0) + item.quantity;
      }
    }
    final rows = revenue.entries
        .map((e) => CategorySales(e.key, e.value, qty[e.key] ?? 0))
        .toList();
    rows.sort((a, b) => b.revenue.compareTo(a.revenue));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final shift = provider.currentShift;
    final completed = provider.completedTransactions;

    // W9 (FR-R2): server-computed outlet-wide splits when online; local
    // computation from cached orders is the offline fallback.
    final rep = provider.serverDashboard;
    final grossSales = rep?.sales ?? shift?.totalSales ?? 0.0;
    final totalExpenses = rep?.expenses ?? provider.todayExpenses;
    final estimatedProfit = grossSales - totalExpenses;

    final byType = _salesByType(completed);
    final Map<String, double> byTender;
    if (rep != null && rep.salesByTender.isNotEmpty) {
      byTender = {
        'cash': rep.salesByTender['cash'] ?? 0,
        'upi': rep.salesByTender['upi'] ?? 0,
        'card': rep.salesByTender['card'] ?? 0,
      }..removeWhere((_, v) => v <= 0);
    } else {
      byTender = _salesByTender(completed);
    }
    final byTypeServer = rep?.salesByType ?? const <String, double>{};
    final categories = rep != null && rep.topCategories.isNotEmpty
        ? rep.topCategories
            .map((c) => CategorySales(c.category, c.revenue, c.quantity))
            .toList()
        : _salesByCategory(completed, provider.menuItems);

    double ratioOf(double amount) =>
        grossSales > 0 ? (amount / grossSales).clamp(0.0, 1.0) : 0.0;

    String amountLabel(double amount) {
      final pct = grossSales > 0 ? (amount / grossSales * 100).toStringAsFixed(0) : '0';
      return '₹${amount.toStringAsFixed(0)} ($pct%)';
    }

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Reports & Analytics', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profit Snapshot Card
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1B18), Color(0xFF2E2925)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ESTIMATED DAILY PROFIT SNAPSHOT',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹${estimatedProfit.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppColors.primaryOrange,
                      fontWeight: FontWeight.w900,
                      fontSize: 36,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Net Sales (₹${grossSales.toStringAsFixed(0)}) − Expenses (₹${totalExpenses.toStringAsFixed(0)}) = Estimated Margin',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Sales By Order Type
            const Text('Sales by Order Type', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Builder(builder: (context) {
                final rows = <Widget>[];
                var shown = 0;
                void addRow(String label, double amount, Color color) {
                  if (amount <= 0) return;
                  if (shown > 0) {
                    rows.add(const Divider(height: 20, color: AppColors.borderLight));
                  }
                  rows.add(_buildProgressRow(label, ratioOf(amount), amountLabel(amount), color));
                  shown++;
                }

                if (byTypeServer.isNotEmpty) {
                  addRow('Dine-In Orders', byTypeServer['dine_in'] ?? 0, AppColors.primaryOrange);
                  addRow('Takeaway / Parcel', byTypeServer['takeaway'] ?? 0, AppColors.vegGreen);
                  addRow('Direct Delivery', byTypeServer['delivery'] ?? 0, AppColors.infoBlue);
                } else {
                  for (final t in OrderType.values) {
                    final entry = byType[t];
                    if (entry == null) continue;
                    addRow(
                      t == OrderType.dineIn
                          ? 'Dine-In Orders'
                          : t == OrderType.takeaway
                              ? 'Takeaway / Parcel'
                              : 'Direct Delivery',
                      entry.amount,
                      t == OrderType.dineIn
                          ? AppColors.primaryOrange
                          : t == OrderType.takeaway
                              ? AppColors.vegGreen
                              : AppColors.infoBlue,
                    );
                  }
                }
                if (shown == 0) {
                  return const Text('No completed orders yet in this shift.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13));
                }
                return Column(children: rows);
              }),
            ),
            const SizedBox(height: 24),

            // Payment Modes Breakdown
            const Text('Payment Mode Distribution', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: byTender.isEmpty
                  ? const Text('No payments collected yet in this shift.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13))
                  : Column(
                      children: [
                        for (final entry in byTender.entries) ...[
                          if (entry.key != byTender.keys.first)
                            const Divider(height: 20, color: AppColors.borderLight),
                          _buildProgressRow(
                            entry.key == 'cash' ? 'Cash' : entry.key == 'upi' ? 'UPI' : entry.key == 'card' ? 'Card' : entry.key,
                            ratioOf(entry.value),
                            amountLabel(entry.value),
                            entry.key.toLowerCase() == 'cash'
                                ? AppColors.vegGreen
                                : entry.key.toLowerCase() == 'upi'
                                    ? AppColors.infoBlue
                                    : AppColors.saffronAmber,
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 24),

            // Top Categories (derived from completed order items)
            const Text('Top Performing Categories', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: categories.isEmpty
                  ? const Text('No item sales recorded yet in this shift.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13))
                  : Column(
                      children: [
                        for (final cat in categories.take(4)) ...[
                          if (cat != categories.first) const Divider(height: 16, color: AppColors.borderLight),
                          _buildCategoryRow(
                            cat.name,
                            '₹${cat.revenue.toStringAsFixed(0)}',
                            '${cat.itemQty} Items',
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildProgressRow(String label, double ratio, String amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Text(amount, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: ratio,
          backgroundColor: AppColors.creamSubtle,
          color: color,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildCategoryRow(String name, String revenue, String orderCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(orderCount, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
            const SizedBox(width: 12),
            Text(revenue, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primaryOrange)),
          ],
        ),
      ],
    );
  }
}

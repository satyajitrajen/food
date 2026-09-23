import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/order_model.dart';
import '../../models/expense_model.dart';
import '../../models/menu_model.dart';
import '../../models/report_model.dart';

class CategorySales {
  final String name;
  final double revenue;
  final int itemQty;
  CategorySales(this.name, this.revenue, this.itemQty);
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // All figures derive from real provider data — no fabricated fallbacks.

  // Period filter: 'Today' | '7D' | '30D' | 'All' | 'Custom'
  String _period = 'Today';
  DateTimeRange? _customRange;
  // Order type filter: 'All' | 'Dine-In' | 'Takeaway' | 'Delivery'
  String _typeFilter = 'All';

  static const Map<String, OrderType> _typeFilters = {
    'Dine-In': OrderType.dineIn,
    'Takeaway': OrderType.takeaway,
    'Delivery': OrderType.delivery,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureServerFetch());
  }

  /// Calendar range backing the selected period chip — used both for local
  /// date math and as the server request key.
  DateTimeRange get _effectiveRange {
    final now = DateTime.now();
    switch (_period) {
      case '7D':
        return DateTimeRange(
            start: now.subtract(const Duration(days: 7)), end: now);
      case '30D':
        return DateTimeRange(
            start: now.subtract(const Duration(days: 30)), end: now);
      case 'All':
        return DateTimeRange(start: DateTime(2000), end: now);
      case 'Custom':
        return _customRange ??
            DateTimeRange(
                start: now.subtract(const Duration(days: 7)), end: now);
      default:
        return DateTimeRange(
            start: DateTime(now.year, now.month, now.day), end: now);
    }
  }

  /// Server-computed outlet-wide stats for the selection. Null when the type
  /// filter is on (server splits can't be re-filtered per type) or the range
  /// fetch hasn't landed yet — Today falls back to the shift dashboard.
  DashboardStats? _serverStatsFor(PosProvider provider) {
    if (_typeFilter != 'All') return null;
    final range = _effectiveRange;
    final rangeRep = provider.serverRangeReport;
    if (rangeRep != null && provider.rangeReportKey == range) return rangeRep;
    if (_period == 'Today') return provider.serverDashboard;
    return null;
  }

  void _ensureServerFetch() {
    final provider = context.read<PosProvider>();
    final range = _effectiveRange;
    if (provider.serverRangeReport == null ||
        provider.rangeReportKey != range) {
      provider.fetchRangeReport(range);
    }
  }

  bool _inPeriod(DateTime ts) {
    switch (_period) {
      case '7D':
        return ts.isAfter(DateTime.now().subtract(const Duration(days: 7)));
      case '30D':
        return ts.isAfter(DateTime.now().subtract(const Duration(days: 30)));
      case 'Custom':
        final r = _customRange;
        if (r == null) return true;
        final start = DateTime(r.start.year, r.start.month, r.start.day);
        final end = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
        return !ts.isBefore(start) && !ts.isAfter(end);
      case 'Today':
        final now = DateTime.now();
        return ts.year == now.year && ts.month == now.month && ts.day == now.day;
      default:
        return true;
    }
  }

  String _periodLabel() {
    switch (_period) {
      case '7D':
        return 'Last 7 days';
      case '30D':
        return 'Last 30 days';
      case 'Custom':
        final r = _customRange;
        if (r == null) return 'Custom';
        final fmt = DateFormat('d MMM');
        return '${fmt.format(r.start)} – ${fmt.format(r.end)}';
      default:
        return _period;
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _period = 'Custom';
      });
      _ensureServerFetch();
    }
  }

  // ---- Aggregation helpers (all operate on the filtered order set) ----

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

  static List<CategorySales> _topItems(List<RestaurantOrder> completed) {
    final revenue = <String, double>{};
    final qty = <String, int>{};
    for (final o in completed) {
      for (final item in o.items) {
        if (item.isCancelled) continue;
        revenue[item.menuItem.name] =
            (revenue[item.menuItem.name] ?? 0.0) + item.totalPrice;
        qty[item.menuItem.name] = (qty[item.menuItem.name] ?? 0) + item.quantity;
      }
    }
    final rows = revenue.entries
        .map((e) => CategorySales(e.key, e.value, qty[e.key] ?? 0))
        .toList();
    rows.sort((a, b) => b.revenue.compareTo(a.revenue));
    return rows;
  }

  static List<CategorySales> _salesByWaiter(List<RestaurantOrder> completed) {
    final revenue = <String, double>{};
    final count = <String, int>{};
    for (final o in completed) {
      final key = (o.waiterName ?? '').isNotEmpty ? o.waiterName! : 'Unassigned';
      revenue[key] = (revenue[key] ?? 0.0) + o.grandTotal;
      count[key] = (count[key] ?? 0) + 1;
    }
    final rows = revenue.entries
        .map((e) => CategorySales(e.key, e.value, count[e.key] ?? 0))
        .toList();
    rows.sort((a, b) => b.revenue.compareTo(a.revenue));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final serverStats = _serverStatsFor(provider);

    // W9 (FR-R2): server-computed outlet-wide truth per selected range (admin
    // + online); local computation from cached orders is the offline fallback.
    final inPeriod = provider.completedTransactions
        .where((o) => _inPeriod(o.paidAt ?? o.createdAt))
        .toList();
    final completed = _typeFilter == 'All'
        ? inPeriod
        : inPeriod.where((o) => o.orderType == _typeFilters[_typeFilter]).toList();

    final filteredExpenses =
        provider.expenses.where((e) => _inPeriod(e.date)).toList();

    final localGross = completed.fold(0.0, (s, o) => s + o.grandTotal);
    final localExpenses = filteredExpenses.fold(0.0, (s, e) => s + e.amount);
    final grossSales = serverStats?.sales ?? localGross;
    final totalExpenses = serverStats?.expenses ?? localExpenses;
    final estimatedProfit = grossSales - totalExpenses;
    final orderCount = serverStats?.orderCount ?? completed.length;
    final aov = orderCount > 0 ? grossSales / orderCount : 0.0;

    final byType = _salesByType(completed);
    final Map<String, double> byTender;
    if (serverStats != null && serverStats.salesByTender.isNotEmpty) {
      byTender = {
        'cash': serverStats.salesByTender['cash'] ?? 0,
        'upi': serverStats.salesByTender['upi'] ?? 0,
        'card': serverStats.salesByTender['card'] ?? 0,
      }..removeWhere((_, v) => v <= 0);
    } else {
      byTender = _salesByTender(completed);
    }
    final byTypeServer = serverStats?.salesByType ?? const <String, double>{};
    final categories =
        serverStats != null && serverStats.topCategories.isNotEmpty
            ? serverStats.topCategories
                .map((c) => CategorySales(c.category, c.revenue, c.quantity))
                .toList()
            : _salesByCategory(completed, provider.menuItems);
    final topItems = _topItems(completed);
    final waiterRows = _salesByWaiter(completed);

    final expenseByCat = <ExpenseCategory, double>{};
    for (final e in filteredExpenses) {
      expenseByCat[e.category] = (expenseByCat[e.category] ?? 0.0) + e.amount;
    }
    final expenseRows = expenseByCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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
        child: Column(
          children: [
            _buildFilterBar(),
            const Divider(height: 1, color: AppColors.borderLight),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Stat Chips
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Orders',
                            '$orderCount',
                            Icons.receipt_long_outlined,
                            AppColors.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Avg Order Value',
                            '₹${aov.toStringAsFixed(0)}',
                            Icons.trending_up_outlined,
                            AppColors.infoBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Gross Sales',
                            '₹${grossSales.toStringAsFixed(0)}',
                            Icons.currency_rupee_outlined,
                            AppColors.vegGreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Expenses',
                            '₹${totalExpenses.toStringAsFixed(0)}',
                            Icons.payments_outlined,
                            AppColors.saffronAmber,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

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
                          Text(
                            'ESTIMATED PROFIT — ${_periodLabel().toUpperCase()}',
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '₹${estimatedProfit.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: estimatedProfit >= 0 ? AppColors.primaryGreen : AppColors.nonVegRed,
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
                    _sectionTitle('Sales by Order Type'),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: _cardDecoration(),
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
                          addRow('Dine-In Orders', byTypeServer['dine_in'] ?? 0, AppColors.primaryGreen);
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
                                  ? AppColors.primaryGreen
                                  : t == OrderType.takeaway
                                      ? AppColors.vegGreen
                                      : AppColors.infoBlue,
                            );
                          }
                        }
                        if (shown == 0) {
                          return _emptyText('No completed orders for this selection yet.');
                        }
                        return Column(children: rows);
                      }),
                    ),
                    const SizedBox(height: 24),

                    // Payment Modes Breakdown
                    _sectionTitle('Payment Mode Distribution'),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: _cardDecoration(),
                      child: byTender.isEmpty
                          ? _emptyText('No payments collected for this selection yet.')
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
                    _sectionTitle('Top Performing Categories'),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: _cardDecoration(),
                      child: categories.isEmpty
                          ? _emptyText('No item sales recorded for this selection yet.')
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
                    const SizedBox(height: 24),

                    // Top Selling Items (revenue leaders for the selection)
                    _sectionTitle('Top Selling Items'),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: _cardDecoration(),
                      child: topItems.isEmpty
                          ? _emptyText('No item sales recorded for this selection yet.')
                          : Column(
                              children: [
                                for (final item in topItems.take(5)) ...[
                                  if (item != topItems.first) const Divider(height: 16, color: AppColors.borderLight),
                                  _buildCategoryRow(
                                    item.name,
                                    '₹${item.revenue.toStringAsFixed(0)}',
                                    '${item.itemQty} Sold',
                                  ),
                                ],
                              ],
                            ),
                    ),
                    const SizedBox(height: 24),

                    // Sales by Waiter
                    _sectionTitle('Staff Performance'),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: _cardDecoration(),
                      child: waiterRows.isEmpty
                          ? _emptyText('No completed orders for this selection yet.')
                          : Column(
                              children: [
                                for (final w in waiterRows.take(5)) ...[
                                  if (w != waiterRows.first) const Divider(height: 16, color: AppColors.borderLight),
                                  _buildCategoryRow(
                                    w.name,
                                    '₹${w.revenue.toStringAsFixed(0)}',
                                    '${w.itemQty} Orders',
                                  ),
                                ],
                              ],
                            ),
                    ),
                    const SizedBox(height: 24),

                    // Expenses by Category
                    _sectionTitle('Expenses by Category'),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: _cardDecoration(),
                      child: expenseRows.isEmpty
                          ? _emptyText('No expenses recorded for this selection yet.')
                          : Column(
                              children: [
                                for (final e in expenseRows) ...[
                                  if (e.key != expenseRows.first.key)
                                    const Divider(height: 20, color: AppColors.borderLight),
                                  _buildProgressRow(
                                    e.key.label,
                                    totalExpenses > 0 ? (e.value / totalExpenses).clamp(0.0, 1.0) : 0.0,
                                    '₹${e.value.toStringAsFixed(0)} (${totalExpenses > 0 ? (e.value / totalExpenses * 100).toStringAsFixed(0) : '0'}%)',
                                    AppColors.saffronAmber,
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Small UI builders ----

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      );

  Text _emptyText(String message) =>
      Text(message, style: const TextStyle(color: AppColors.textMuted, fontSize: 13));

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      );

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in const ['Today', '7D', '30D', 'All', 'Custom'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p == 'Custom' ? 'Custom${_period == 'Custom' ? '' : '…'}' : p),
                      selected: _period == p,
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: _period == p ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      onSelected: (_) {
                        if (p == 'Custom') {
                          _pickCustomRange();
                        } else {
                          setState(() => _period = p);
                          _ensureServerFetch();
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in ['All', ..._typeFilters.keys])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t),
                      selected: _typeFilter == t,
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: _typeFilter == t ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      onSelected: (_) => setState(() => _typeFilter = t),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
            Text(revenue, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primaryGreen)),
          ],
        ),
      ],
    );
  }
}

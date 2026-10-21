import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/order_model.dart';
import '../../models/expense_model.dart';
import '../../models/menu_model.dart';
import '../../models/report_model.dart';
import '../../core/api/dto.dart';
import '../../core/format.dart';
import '../../core/share/report_pdf.dart';

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
    // Whole calendar days (no time of day), so the same selection produces
    // the same key all day long and the cached server report is reused.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    switch (_period) {
      case '7D':
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case '30D':
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
      case 'All':
        return DateTimeRange(start: DateTime(2000), end: today);
      case 'Custom':
        final r = _customRange;
        return r == null
            ? DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today)
            : DateTimeRange(start: day(r.start), end: day(r.end));
      default:
        return DateTimeRange(start: today, end: today);
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
      final key = PaymentMethodX.fromLabel(o.paymentMethod).name;
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

  /// Aggregates the currently filtered report view into the flat structure
  /// shared by the UI and the PDF download, so a downloaded report always
  /// matches what is on screen (server truth when available, local cache
  /// computed offline otherwise).
  ReportSnapshot _buildSnapshot(PosProvider provider) {
    final serverStats = _serverStatsFor(provider);

    // W9 (FR-R2): server-computed outlet-wide truth per selected range (admin
    // + online); local computation from cached orders is the offline fallback.
    final inPeriod = provider.completedTransactions
        .where((o) => _inPeriod(o.paidAt ?? o.createdAt))
        .toList();
    final completed = _typeFilter == 'All'
        ? inPeriod
        : inPeriod.where((o) => o.orderType == _typeFilters[_typeFilter]).toList();
    // Expenses carry no order type: under a type filter they'd mix unfiltered
    // spend with filtered sales, so both the Expenses card and Estimated
    // Profit render an em dash instead of a number.
    final typeFiltered = _typeFilter != 'All';

    final filteredExpenses =
        provider.expenses.where((e) => _inPeriod(e.date)).toList();

    final localGross = completed.fold(0.0, (s, o) => s + o.grandTotal);
    final localExpenses = filteredExpenses.fold(0.0, (s, e) => s + e.amount);
    final localRefunds = completed.fold(0.0, (s, o) => s + o.refundedAmount);
    final grossSales = serverStats?.sales ?? localGross;
    final refunds = serverStats?.refunds ?? localRefunds;
    final netSales = serverStats?.netSales ?? (localGross - localRefunds);
    final totalExpenses = serverStats?.expenses ?? localExpenses;
    final estimatedProfit = netSales - totalExpenses;
    final orderCount = serverStats?.orderCount ?? completed.length;
    final aov = orderCount > 0 ? grossSales / orderCount : 0.0;

    final byTypeServer = serverStats?.salesByType ?? const <String, double>{};
    final typeRows = <ReportRow>[];
    void addType(String label, double amount) {
      if (amount > 0) typeRows.add(ReportRow(label, amount));
    }

    if (byTypeServer.isNotEmpty) {
      addType('Dine-In Orders', byTypeServer['dine_in'] ?? 0);
      addType('Takeaway / Parcel', byTypeServer['takeaway'] ?? 0);
      addType('Direct Delivery', byTypeServer['delivery'] ?? 0);
    } else {
      for (final entry in _salesByType(completed).entries) {
        addType(
          entry.key == OrderType.dineIn
              ? 'Dine-In Orders'
              : entry.key == OrderType.takeaway
                  ? 'Takeaway / Parcel'
                  : 'Direct Delivery',
          entry.value.amount,
        );
      }
    }

    final Map<String, double> byTender;
    if (serverStats != null && serverStats.salesByTender.isNotEmpty) {
      byTender = {
        'cash': serverStats.salesByTender['cash'] ?? 0,
        'upi': serverStats.salesByTender['upi'] ?? 0,
        'card': serverStats.salesByTender['card'] ?? 0,
        'credit': serverStats.salesByTender['credit'] ?? 0,
      }..removeWhere((_, v) => v <= 0);
    } else {
      byTender = _salesByTender(completed);
    }
    final tenderRows = byTender.entries
        .map((e) => ReportRow(PaymentMethodX.fromLabel(e.key).label, e.value))
        .toList();

    List<ReportRow> toRows(List<CategorySales> rows) => rows
        .map((c) => ReportRow(c.name, c.revenue, count: c.itemQty))
        .toList();

    // Server truth across all terminals when available; this terminal's
    // cached orders otherwise.
    final categories =
        serverStats != null && serverStats.topCategories.isNotEmpty
            ? toRows(serverStats.topCategories
                .map((c) => CategorySales(c.category, c.revenue, c.quantity))
                .toList())
            : toRows(_salesByCategory(completed, provider.menuItems));
    final topItems = serverStats != null && serverStats.topItems.isNotEmpty
        ? toRows(serverStats.topItems
            .map((c) => CategorySales(c.category, c.revenue, c.quantity))
            .toList())
        : toRows(_topItems(completed));
    final waiterRows = serverStats != null && serverStats.staffSales.isNotEmpty
        ? toRows(serverStats.staffSales
            .map((w) => CategorySales(w.staffName, w.revenue, w.orderCount))
            .toList())
        : toRows(_salesByWaiter(completed));

    final expenseByCat = <ExpenseCategory, double>{};
    if (serverStats != null && serverStats.expensesByCategory.isNotEmpty) {
      serverStats.expensesByCategory.forEach((k, v) {
        final cat = expenseCategoryFromApi(k);
        expenseByCat[cat] = (expenseByCat[cat] ?? 0.0) + v;
      });
    } else {
      for (final e in filteredExpenses) {
        expenseByCat[e.category] = (expenseByCat[e.category] ?? 0.0) + e.amount;
      }
    }
    final expenseRows = expenseByCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ReportSnapshot(
      restaurantName: provider.settings.restaurantName,
      periodLabel: _periodLabel(),
      typeLabel: 'Order type: $_typeFilter',
      orderCount: orderCount,
      grossSales: grossSales,
      refunds: refunds,
      netSales: netSales,
      totalExpenses: totalExpenses,
      estimatedProfit: estimatedProfit,
      aov: aov,
      typeFiltered: typeFiltered,
      salesByType: typeRows,
      salesByTender: tenderRows,
      topCategories: categories.take(4).toList(),
      topItems: topItems.take(5).toList(),
      staffSales: waiterRows.take(5).toList(),
      expensesByCategory:
          expenseRows.map((e) => ReportRow(e.key.label, e.value)).toList(),
    );
  }

  /// Saves + shares the on-screen report as a PDF.
  Future<void> _downloadReport() async {
    final snapshot = _buildSnapshot(context.read<PosProvider>());
    final messenger = ScaffoldMessenger.of(context);
    final message = await ReportPdf.share(snapshot);
    messenger.showSnackBar(SnackBar(
      content: Text(message ?? 'Report PDF ready to share'),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final r = _buildSnapshot(provider);

    double ratioOf(double amount) =>
        r.grossSales > 0 ? (amount / r.grossSales).clamp(0.0, 1.0) : 0.0;

    String amountLabel(double amount) {
      final pct =
          r.grossSales > 0 ? (amount / r.grossSales * 100).toStringAsFixed(0) : '0';
      return '${formatInr(amount)} ($pct%)';
    }

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Download report',
            icon: const Icon(Icons.download_outlined),
            onPressed: _downloadReport,
          ),
        ],
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
                            '${r.orderCount}',
                            Icons.receipt_long_outlined,
                            AppColors.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Avg Order Value',
                            formatInr(r.aov),
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
                            r.refunds > 0 ? 'Net sales (after ${formatInr(r.refunds)} refunds)' : 'Net sales',
                            formatInr(r.netSales),
                            Icons.currency_rupee_outlined,
                            AppColors.vegGreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            'Expenses',
                            r.typeFiltered ? '—' : formatInr(r.totalExpenses),
                            Icons.payments_outlined,
                            AppColors.saffronAmber,
                            subline: r.typeFiltered ? 'not attributed by order type' : null,
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
                            r.typeFiltered ? '—' : formatInr(r.estimatedProfit),
                            style: TextStyle(
                              color: r.typeFiltered
                                  ? Colors.white70
                                  : (r.estimatedProfit >= 0 ? AppColors.brandGreen : const Color(0xFFFF8A80)),
                              fontWeight: FontWeight.w900,
                              fontSize: 36,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            r.typeFiltered
                                ? 'Expenses are not attributed by order type'
                                : 'Net sales ${formatInr(r.netSales)} − expenses ${formatInr(r.totalExpenses)}',
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
                      child: r.salesByType.isEmpty
                          ? _emptyText('No completed orders for this selection yet.')
                          : Column(
                              children: [
                                for (final (i, row) in r.salesByType.indexed) ...[
                                  if (i > 0) const Divider(height: 20, color: AppColors.borderLight),
                                  _buildProgressRow(
                                    row.label,
                                    ratioOf(row.amount),
                                    amountLabel(row.amount),
                                    _typeRowColor(row.label),
                                  ),
                                ],
                              ],
                            ),
                    ),
                    const SizedBox(height: 24),

                    // Payment Modes Breakdown
                    _sectionTitle('Payment Mode Distribution'),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: _cardDecoration(),
                      child: r.salesByTender.isEmpty
                          ? _emptyText('No payments collected for this selection yet.')
                          : Column(
                              children: [
                                for (final (i, row) in r.salesByTender.indexed) ...[
                                  if (i > 0) const Divider(height: 20, color: AppColors.borderLight),
                                  _buildProgressRow(
                                    row.label,
                                    ratioOf(row.amount),
                                    amountLabel(row.amount),
                                    row.label.toLowerCase() == 'cash'
                                        ? AppColors.vegGreen
                                        : row.label.toLowerCase() == 'upi'
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
                      child: r.topCategories.isEmpty
                          ? _emptyText('No item sales recorded for this selection yet.')
                          : Column(
                              children: [
                                for (final (i, cat) in r.topCategories.indexed) ...[
                                  if (i > 0) const Divider(height: 16, color: AppColors.borderLight),
                                  _buildCategoryRow(
                                    cat.label,
                                    formatInr(cat.amount),
                                    plural(cat.count, 'item'),
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
                      child: r.topItems.isEmpty
                          ? _emptyText('No item sales recorded for this selection yet.')
                          : Column(
                              children: [
                                for (final (i, item) in r.topItems.indexed) ...[
                                  if (i > 0) const Divider(height: 16, color: AppColors.borderLight),
                                  _buildCategoryRow(
                                    item.label,
                                    formatInr(item.amount),
                                    '${item.count} Sold',
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
                      child: r.staffSales.isEmpty
                          ? _emptyText('No completed orders for this selection yet.')
                          : Column(
                              children: [
                                for (final (i, w) in r.staffSales.indexed) ...[
                                  if (i > 0) const Divider(height: 16, color: AppColors.borderLight),
                                  _buildCategoryRow(
                                    w.label,
                                    formatInr(w.amount),
                                    plural(w.count, 'order'),
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
                      child: r.expensesByCategory.isEmpty
                          ? _emptyText('No expenses recorded for this selection yet.')
                          : Column(
                              children: [
                                for (final (i, e) in r.expensesByCategory.indexed) ...[
                                  if (i > 0) const Divider(height: 20, color: AppColors.borderLight),
                                  _buildProgressRow(
                                    e.label,
                                    r.totalExpenses > 0 ? (e.amount / r.totalExpenses).clamp(0.0, 1.0) : 0.0,
                                    '${formatInr(e.amount)} (${r.totalExpenses > 0 ? (e.amount / r.totalExpenses * 100).toStringAsFixed(0) : '0'}%)',
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

  Color _typeRowColor(String label) => label == 'Dine-In Orders'
      ? AppColors.primaryGreen
      : label == 'Takeaway / Parcel'
          ? AppColors.vegGreen
          : AppColors.infoBlue;

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

  Widget _buildStatCard(String label, String value, IconData icon, Color color, {String? subline}) {
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
          if (subline != null)
            Text(
              subline,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
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

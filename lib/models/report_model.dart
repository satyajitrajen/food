/// Server-computed shift dashboard (GET /api/v1/reports/dashboard).
/// Money arrives in integer paise and is converted to rupees at the API edge;
/// these numbers are outlet-wide truth across all terminals.
class DashboardStats {
  final double sales;
  final int orderCount;
  final double aov;
  final double expenses;
  final double cashDrawer;
  final int pendingKots;

  /// FR-R2 splits straight from the server (money in rupees).
  final Map<String, double> salesByType;
  final Map<String, double> salesByTender;
  final List<CategorySales> topCategories;

  const DashboardStats({
    required this.sales,
    required this.orderCount,
    required this.aov,
    required this.expenses,
    required this.cashDrawer,
    required this.pendingKots,
    this.salesByType = const {},
    this.salesByTender = const {},
    this.topCategories = const [],
  });
}

class CategorySales {
  final String category;
  final double revenue;
  final int quantity;

  const CategorySales({required this.category, required this.revenue, required this.quantity});
}


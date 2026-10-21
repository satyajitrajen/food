import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/share/report_pdf.dart';

void main() {
  test('ReportPdf builds a non-empty PDF from a snapshot', () async {
    const snapshot = ReportSnapshot(
      restaurantName: 'Test Kitchen',
      periodLabel: 'Today',
      typeLabel: 'Order type: All',
      orderCount: 12,
      grossSales: 5430,
      refunds: 120,
      netSales: 5310,
      totalExpenses: 900,
      estimatedProfit: 4410,
      aov: 452.5,
      typeFiltered: false,
      salesByType: [
        ReportRow('Dine-In Orders', 4000, count: 9),
        ReportRow('Takeaway / Parcel', 1310, count: 3),
      ],
      salesByTender: [ReportRow('Cash', 3000), ReportRow('UPI', 2310)],
      topCategories: [ReportRow('Starters', 2500, count: 20)],
      topItems: [ReportRow('Paneer Tikka', 1200, count: 8)],
      staffSales: [ReportRow('Rahul', 3000, count: 7)],
      expensesByCategory: [ReportRow('Groceries', 600)],
    );

    final bytes = await ReportPdf.buildPdf(snapshot);
    expect(bytes.length, greaterThan(1000));
    // PDF files start with the %PDF- magic.
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });
}

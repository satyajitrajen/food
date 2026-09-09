import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/main.dart';
import 'package:food_pos/providers/pos_provider.dart';
import 'package:food_pos/models/shift_model.dart';
import 'package:food_pos/models/table_model.dart';
import 'package:food_pos/models/order_model.dart';
import 'package:food_pos/models/kot_model.dart';
import 'package:food_pos/models/expense_model.dart';
import 'package:food_pos/screens/dashboard/pos_dashboard_screen.dart';
import 'package:food_pos/screens/order_flow/table_selection_screen.dart';
import 'package:provider/provider.dart';

// Mock HttpOverrides so NetworkImage doesn't fail in headless test environment
class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _createMockHttpClient();
  }
}

HttpClient _createMockHttpClient() {
  final client = _MockHttpClient();
  return client;
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientResponse implements HttpClientResponse {
  static final List<int> _transparentImage = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
    0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
    0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
    0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
    0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
    0x60, 0x82,
  ];

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _transparentImage.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(_transparentImage).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() {
    HttpOverrides.global = TestHttpOverrides();
  });

  group('Resto POS Unit & Widget Tests', () {
    testWidgets('App renders splash screen and transitions to PIN login', (WidgetTester tester) async {
      await tester.pumpWidget(const RestoPosApp());
      expect(find.text('RESTO POS'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // After splash, should transition to staff login with avatar & title
      expect(find.text('Rahul Sharma'), findsOneWidget);
    });

    testWidgets('POS Dashboard displays operational KPIs and floor glance', (WidgetTester tester) async {
      final provider = PosProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: PosDashboardScreen(),
          ),
        ),
      );

      expect(find.text("Today's Sales"), findsOneWidget);
      expect(find.text("Table Floor Status"), findsOneWidget);
      expect(find.text("Quick Operational Actions"), findsOneWidget);
    });

    testWidgets('Table Selection screen displays floor tables', (WidgetTester tester) async {
      final provider = PosProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: TableSelectionScreen(),
          ),
        ),
      );

      expect(find.text("Floor Tables"), findsOneWidget);
      expect(find.text("Ground Floor"), findsOneWidget);
      expect(find.text("T01"), findsOneWidget);
      expect(find.text("T05"), findsOneWidget);
    });

    test('Cash Drawer Expected Cash formula calculates correctly', () {
      final shift = Shift(
        id: 'SH-test',
        staffId: 'st-01',
        staffName: 'Rahul',
        startedAt: DateTime.now(),
        openingCash: 5000.0,
        cashSales: 3000.0,
        cashIn: 500.0,
        expenses: 1200.0,
        refundsCash: 200.0,
        cashOut: 100.0,
      );

      // Expected = 5000 + 3000 + 500 - 1200 - 200(cash refund) - 100 = 7000
      expect(shift.expectedCash, 7000.0);
    });

    test('Digital refunds do not reduce expected drawer cash', () {
      final shift = Shift(
        id: 'SH-test2',
        staffId: 'st-01',
        staffName: 'Rahul',
        startedAt: DateTime.now(),
        openingCash: 5000.0,
        cashSales: 3000.0,
        refundsDigital: 200.0,
      );
      // Expected = 5000 + 3000 = 8000 (UPI refund never touches the drawer)
      expect(shift.expectedCash, 8000.0);
      expect(shift.refunds, 200.0);
    });

    test('Cash Denomination total calculation', () {
      final denoms = CashDenomination(
        count500: 4, // 2000
        count200: 5, // 1000
        count100: 10, // 1000
        count50: 2, // 100
      );
      expect(denoms.total, 4100.0);
    });

    test('PosProvider cart and billing calculations', () {
      final provider = PosProvider();
      expect(provider.tables.isNotEmpty, true);
      expect(provider.menuItems.isNotEmpty, true);

      // Select table T05
      final table = provider.tables.firstWhere((t) => t.tableNumber == 'T05');
      provider.selectTable(table);

      // Add Paneer Tikka (₹280)
      final paneerTikka = provider.menuItems.firstWhere((m) => m.name == 'Paneer Tikka');
      provider.addToCart(paneerTikka);

      expect(provider.activeOrder?.items.length, 1);
      expect(provider.activeOrder?.subtotal, 280.0);

      // Add 10% discount
      provider.applyDiscount(percent: 10);
      expect(provider.activeOrder?.computedDiscount, 28.0);
      expect(provider.activeOrder?.netTaxable, 252.0);

      // 5% GST on 252 = 12.6
      expect(provider.activeOrder?.computedTax, 12.6);
    });

    test('Full End-to-End Operational Lifecycle: Open Shift -> Order -> KOT -> Kitchen -> Payment -> Expense -> Close Shift', () {
      final provider = PosProvider();

      // 1. Open Shift with float of 5000
      provider.openShift(openingCash: 5000.0, notes: 'Morning Breakfast Shift');
      expect(provider.currentShift, isNotNull);
      expect(provider.currentShift!.openingCash, 5000.0);
      expect(provider.currentShift!.isClosed, false);

      // 2. Select Table T01 and Start Order
      final table = provider.tables.firstWhere((t) => t.tableNumber == 'T01');
      provider.selectTable(table);
      expect(provider.activeOrder, isNotNull);
      expect(provider.activeOrder!.tableNumber, 'T01');

      // 3. Add items to cart
      final paneerTikka = provider.menuItems.firstWhere((m) => m.name == 'Paneer Tikka');
      final butterNaan = provider.menuItems.firstWhere((m) => m.name == 'Butter Naan');
      provider.addToCart(paneerTikka); // 280
      provider.addToCart(butterNaan);  // 50
      provider.addToCart(butterNaan);  // 50 -> quantity 2 (total 100)
      expect(provider.activeOrder!.subtotal, 380.0);

      // 4. Send KOT to Kitchen
      final kot = provider.sendKOT();
      expect(kot, isNotNull);
      expect(kot!.status, KOTStatus.newTicket);
      expect(table.status, TableStatus.occupied);
      expect(table.activeOrderId, isNotNull);

      // 5. Kitchen processes KOT (New -> Preparing -> Ready -> Served)
      provider.updateKOTStatus(kot.id, KOTStatus.preparing);
      expect(provider.kots.firstWhere((k) => k.id == kot.id).status, KOTStatus.preparing);
      provider.updateKOTStatus(kot.id, KOTStatus.ready);
      expect(provider.kots.firstWhere((k) => k.id == kot.id).status, KOTStatus.ready);
      provider.updateKOTStatus(kot.id, KOTStatus.served);
      expect(provider.kots.firstWhere((k) => k.id == kot.id).status, KOTStatus.served);

      // 6. Apply 10% Bill Discount
      provider.applyDiscount(percent: 10, reason: 'Happy Hours Promo');
      // Subtotal 380 - 38 = 342 net taxable
      expect(provider.activeOrder!.netTaxable, 342.0);
      // 5% GST = 17.1 -> Grand Total = 359.1
      expect(provider.activeOrder!.grandTotal, closeTo(359.1, 0.01));

      // 7. Complete Cash Payment
      final grandTotal = provider.activeOrder!.grandTotal;
      final initialCashSales = provider.currentShift!.cashSales;
      final completedOrder = provider.completePayment(
        paymentMethod: 'Cash',
        amountPaid: 400.0,
      );
      expect(completedOrder, isNotNull);
      expect(completedOrder!.status, OrderStatus.completed);
      expect(completedOrder.invoiceNumber, isNotNull);
      // Table freed up
      expect(table.status, TableStatus.available);
      expect(table.activeOrderId, isNull);
      // Cash recorded into shift
      expect(provider.currentShift!.cashSales, initialCashSales + grandTotal);

      // 8. Record a Cash Expense (e.g. Dairy / Milk purchase)
      final initialExpenses = provider.currentShift!.expenses;
      provider.addExpense(
        Expense(
          id: 'exp-test',
          title: 'Daily Dairy & Milk',
          category: ExpenseCategory.rawMaterials,
          amount: 500.0,
          date: DateTime.now(),
          paymentMethod: 'Cash',
          vendor: 'Gokul Dairy',
        ),
      );
      expect(provider.currentShift!.expenses, initialExpenses + 500.0);

      // 9. Close Shift with Denomination Count
      final expectedCash = provider.currentShift!.expectedCash;
      expect(expectedCash, greaterThan(0));

      final closingDenoms = CashDenomination(
        count500: (expectedCash / 500).floor(),
        count100: ((expectedCash % 500) / 100).floor(),
      );

      provider.closeShift(
        actualCash: expectedCash,
        notes: 'Shift balanced cleanly',
        denominations: closingDenoms,
      );
      expect(provider.shiftHistory.first.isClosed, true);
      expect(provider.shiftHistory.first.cashDifference, 0.0);
      expect(provider.shiftHistory.length, 1);
    });
  });
}

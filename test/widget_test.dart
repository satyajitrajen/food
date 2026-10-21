import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixtures/pos_fixtures.dart';
import 'package:food_pos/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:food_pos/models/shift_model.dart';
import 'package:food_pos/models/table_model.dart';
import 'package:food_pos/models/order_model.dart';
import 'package:food_pos/models/kot_model.dart';
import 'package:food_pos/models/expense_model.dart';
import 'package:food_pos/models/inventory_model.dart';
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
    // Boot reads SharedPreferences (tenant/session restore): resolve instantly.
    SharedPreferences.setMockInitialValues({});
  });

  group('Resto POS Unit & Widget Tests', () {
    testWidgets('Without a server the app waits on the No connection screen', (WidgetTester tester) async {
      await tester.pumpWidget(const RestoPosApp());
      expect(find.text('Connecting to the server...'), findsOneWidget);
      // Boot gives up on the unreachable server; the app is online-only, so
      // it does not continue to setup/login but shows why it is waiting.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('No connection'), findsOneWidget);
    });

    testWidgets('POS Dashboard displays operational KPIs and floor glance', (WidgetTester tester) async {
      final provider = fixtureProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: PosDashboardScreen(),
          ),
        ),
      );

      expect(find.text('Shift sales'), findsOneWidget);
      expect(find.text("Table Floor Status"), findsOneWidget);
      expect(find.text("Quick Operational Actions"), findsOneWidget);
    });

    testWidgets('POS Dashboard zeroes financial KPIs when no shift is open', (WidgetTester tester) async {
      final provider = fixtureProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: PosDashboardScreen(),
          ),
        ),
      );

      // No shift → the counter is not trading: all money KPIs read zero.
      expect(find.text('₹0'), findsWidgets);
      expect(find.text('₹500'), findsNothing);
    });

    testWidgets('POS Dashboard shows the live shift and resets after close', (WidgetTester tester) async {
      final provider = fixtureProvider();
      await provider.openShift(openingCash: 500);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: PosDashboardScreen(),
          ),
        ),
      );

      // Fresh shift: opening float sits in the drawer, nothing sold yet.
      expect(find.text('₹500'), findsOneWidget);
      expect(find.text('₹0'), findsWidgets);

      await provider.closeShift(actualCash: 500);
      await tester.pump();

      // Shift closed → dashboard hands over clean.
      expect(find.text('₹500'), findsNothing);
    });

    testWidgets('Table Selection screen displays floor tables', (WidgetTester tester) async {
      final provider = fixtureProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: TableSelectionScreen(),
          ),
        ),
      );

      expect(find.text("Floor Tables"), findsOneWidget);
      expect(find.text("All sections"), findsOneWidget); // section dropdown
      expect(find.text("T01"), findsOneWidget);
      expect(find.text("T05"), findsOneWidget);
    });

    test('Record Purchase mirrors stock intake into local inventory', () {
      final provider = fixtureProvider();
      provider.addInventoryItem(InventoryItem(
        id: 'inv-1',
        name: 'Paneer',
        availableStock: 5.0,
        minStock: 2.0,
        unit: 'KG',
        costPerUnit: 100.0,
      ));

      provider.createPurchase(
        invoiceNo: 'INV-77',
        status: 'paid',
        totalAmount: 650,
        lines: [
          {'inventory_item_id': 'inv-1', 'name': 'Paneer', 'qty': 10, 'unit_cost_paise': 5000},
          // Unknown id and non-positive qty must be skipped, not crash.
          {'inventory_item_id': 'inv-404', 'name': 'Ghost', 'qty': 3, 'unit_cost_paise': 100},
          {'inventory_item_id': 'inv-1', 'name': 'Paneer', 'qty': 0, 'unit_cost_paise': 100},
        ],
      );

      expect(
        provider.inventory.firstWhere((i) => i.id == 'inv-1').availableStock,
        15.0,
      );
    });

    test('Orders are attributed to the logged-in staff regardless of role', () async {
      final provider = fixtureProvider();
      // Priya is a manager: billing is attributed to her, not left unassigned.
      expect(await provider.loginStaffById('st-02', '9999'), isTrue);

      provider.startNewOrder(OrderType.takeaway);
      expect(provider.activeOrder!.waiterId, 'st-02');
      expect(provider.activeOrder!.waiterName, 'Priya Joshi');

      // Table path: creator attribution with an assigned-waiter override.
      final table = provider.tables.firstWhere((t) => t.tableNumber == 'T02');
      table.assignedWaiter = 'Amit Deshmukh';
      provider.selectTable(table);
      expect(provider.activeOrder!.waiterId, 'st-02');
      expect(provider.activeOrder!.waiterName, 'Amit Deshmukh');
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
      final provider = fixtureProvider();
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

    test('Full End-to-End Operational Lifecycle: Open Shift -> Order -> KOT -> Kitchen -> Payment -> Expense -> Close Shift', () async {
      final provider = fixtureProvider();

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
      final completedOrder = (await provider.completePayment(
        paymentMethod: 'Cash',
        amountPaid: 400.0,
      )).order;
      expect(completedOrder, isNotNull);
      expect(completedOrder!.status, OrderStatus.completed);
      // Invoice numbers are server-assigned (GST-sequential), never local.
      expect(completedOrder.invoiceNumber, isNull);
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

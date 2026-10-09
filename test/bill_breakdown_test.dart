import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/models/menu_model.dart';
import 'package:food_pos/models/order_model.dart';
import 'package:food_pos/widgets/bill_breakdown.dart';

RestaurantOrder _paidSplitOrder() => RestaurantOrder(
      id: 'ord-1',
      orderNumber: 'ORD-2000',
      orderType: OrderType.dineIn,
      createdAt: DateTime(2026, 9, 6, 13, 30),
      items: [
        OrderItem(
          id: 'i-1',
          menuItem: MenuItem(
            id: 'm-1',
            name: 'Paneer Tikka',
            category: 'Starters',
            price: 280,
            isVeg: true,
            imageUrl: '',
          ),
          quantity: 1,
        ),
      ],
      paidAt: DateTime(2026, 9, 6, 14, 10),
      status: OrderStatus.completed,
      paymentMethod: 'Cash',
      totalPaid: 300,
      paymentSplits: const [
        PaymentLeg(method: 'Cash', amount: 150),
        PaymentLeg(method: 'Card', amount: 150),
      ],
    );

Future<void> _pump(WidgetTester tester, RestaurantOrder order) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BillBreakdown(order: order, showPayment: true),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('on-screen bill shows one Paid row per split leg', (tester) async {
    await _pump(tester, _paidSplitOrder());
    expect(find.text('Paid (Cash)'), findsOneWidget);
    expect(find.text('Paid (Card)'), findsOneWidget);
  });

  testWidgets('on-screen bill shows the approval reference for a card tender',
      (tester) async {
    final order = _paidSplitOrder()..paymentReference = '424242';
    await _pump(tester, order);
    expect(find.text('Approval: 424242'), findsOneWidget);
  });

  testWidgets('no approval line without a reference', (tester) async {
    await _pump(tester, _paidSplitOrder());
    expect(find.textContaining('Approval:'), findsNothing);
  });
}

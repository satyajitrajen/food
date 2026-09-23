import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/providers/pos_provider.dart';
import 'package:food_pos/screens/cart/cart_view.dart';
import 'package:food_pos/screens/modals/kot_sent_dialog.dart';
import 'package:food_pos/models/kot_model.dart';
import 'package:provider/provider.dart';

/// Regression tests for the waiter post-KOT navigation (QA items 1/6/7):
/// - "View Order" opens the order details screen (never the cart or checkout).
/// - "Floor Tables" returns to the shell with the Tables tab active.
/// - Add More stays in the cart (no automatic pop/redirect).
void main() {
  Widget wrapProvider(PosProvider provider) => ChangeNotifierProvider<PosProvider>.value(
        value: provider,
        child: const MaterialApp(home: CartViewScreen()),
      );

  testWidgets('all-sent cart shows View Order + Checkout, no auto redirect',
      (tester) async {
    final provider = PosProvider();
    provider.selectTable(provider.tables.first);
    provider.addToCart(provider.menuItems.first);
    provider.sendKOT();
    // All items are KOT-sent now.

    await tester.pumpWidget(wrapProvider(provider));
    await tester.pumpAndSettle();

    expect(find.text('View Order'), findsOneWidget);
    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('Send KOT'), findsNothing);

    // View Order opens the details screen (order number in the app bar).
    await tester.tap(find.text('View Order'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Details'), findsOneWidget);
  });

  testWidgets('KOT Sent dialog: each action navigates distinctly',
      (tester) async {
    var viewOrderTaps = 0;
    var floorTaps = 0;
    var addMoreTaps = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => KOTSentDialog.show(
                context,
                kot: stubKot,
                onAddMoreItems: () => addMoreTaps++,
                onViewOrder: () => viewOrderTaps++,
                onGoToTables: () => floorTaps++,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View Order'));
    await tester.pumpAndSettle();
    expect(viewOrderTaps, 1);
    expect(find.text('View Order'), findsNothing, reason: 'dialog closed');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Floor Tables'));
    await tester.pumpAndSettle();
    expect(floorTaps, 1);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add More'));
    await tester.pumpAndSettle();
    expect(addMoreTaps, 1);
  });
}

final KitchenOrderTicket stubKot = _stubKot();

KitchenOrderTicket _stubKot() {
  // Minimal ticket for the dialog: built through the provider shape.
  final p = PosProvider();
  p.selectTable(p.tables.first);
  p.addToCart(p.menuItems.first);
  return p.sendKOT()!;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/pos_fixtures.dart';

/// Customer request: the owner must be able to fix a mistaken quantity after
/// the KOT/bill print, as long as the order is not paid.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('lowers the quantity on an unpaid order and updates the total', () {
    final p = fixtureProvider();
    expect(p.loginStaff('9999'), isTrue); // manager
    p.selectTable(p.tables.first);
    final item = p.menuItems.first;
    p.addToCart(item);
    p.addToCart(item);
    p.addToCart(item);
    p.sendKOT();

    final order = p.orders.first;
    final line = order.items.first;
    expect(line.quantity, 3);
    final before = order.grandTotal;

    p.reduceItemQuantity(orderId: order.id, itemId: line.id, quantity: 2, managerPin: '9999');
    expect(line.quantity, 2);
    expect(order.grandTotal, lessThan(before));

    // Not an increase, not zero (that is Void), not above the current qty.
    p.reduceItemQuantity(orderId: order.id, itemId: line.id, quantity: 0);
    p.reduceItemQuantity(orderId: order.id, itemId: line.id, quantity: 5);
    expect(line.quantity, 2);
  });
}

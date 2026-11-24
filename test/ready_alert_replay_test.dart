import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/pos_fixtures.dart';

/// Customer report: the "Order Ready — serve now!" banner kept coming back
/// (+9 stacked) even after "Dismiss all". Replayed/re-delivered KOT events
/// must not resurrect dismissed or already-served tickets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Map<String, dynamic> kot(String id, String status) => {
        'id': id,
        'outlet_id': 'out-01',
        'kot_number': 'KOT #$id',
        'order_id': 'ord-$id',
        'table_number': 'T01',
        'order_type': 'dine_in',
        'waiter_name': 'Amit Deshmukh',
        'status': status,
        'items': const [],
      };

  test('dismissed ready tickets do not alert again on a replayed event', () {
    final p = fixtureProvider();
    expect(p.loginStaff('1111'), isTrue); // waiter Amit Deshmukh

    p.debugApplyRealtimeEvent('kot.updated', kot('k1', 'preparing'));
    p.debugApplyRealtimeEvent('kot.updated', kot('k1', 'ready'));
    p.debugApplyRealtimeEvent('kot.updated', kot('k2', 'ready'));
    expect(p.readyAlertCount, 2);

    p.dismissAllReadyAlerts();
    expect(p.readyAlertCount, 0);

    // Same history delivered again (reconnect replay).
    p.debugApplyRealtimeEvent('kot.updated', kot('k1', 'preparing'));
    p.debugApplyRealtimeEvent('kot.updated', kot('k1', 'ready'));
    p.debugApplyRealtimeEvent('kot.updated', kot('k2', 'ready'));
    expect(p.readyAlertCount, 0);

    // A genuinely new ticket still alerts.
    p.debugApplyRealtimeEvent('kot.updated', kot('k3', 'ready'));
    expect(p.readyAlertCount, 1);
  });

  test('a ticket served on another device drops its ready banner', () {
    final p = fixtureProvider();
    expect(p.loginStaff('1111'), isTrue);

    p.debugApplyRealtimeEvent('kot.updated', kot('k1', 'ready'));
    expect(p.readyAlertCount, 1);

    p.debugApplyRealtimeEvent('kot.updated', kot('k1', 'served'));
    expect(p.readyAlertCount, 0);
  });
}

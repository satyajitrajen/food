import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/api/dto.dart';
import 'package:food_pos/core/sync/outbox.dart';
import 'package:food_pos/models/order_model.dart';
import 'package:food_pos/models/settings_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('money convention (paise at the API edge)', () {
    test('toPaise rounds half-up', () {
      expect(toPaise(280.0), 28000);
      expect(toPaise(10.005), 1001);
      expect(toPaise(0.005), 1);
    });

    test('toRupees divides', () {
      expect(toRupees(28000), 280.0);
      expect(toRupees(1), 0.01);
    });
  });

  group('orderFromApi', () {
    test('maps a server order with client_id and modifier lines', () {
      final json = {
        'id': 'ord-srv-1',
        'client_id': 'ord-local-9',
        'outlet_id': 'out-01',
        'order_number': 'ORD-1050',
        'type': 'dine_in',
        'status': 'preparing',
        'table_id': 't-01',
        'table_number': 'T01',
        'guest_count': 3,
        'tax_percent': 5.0,
        'discount_percent': 0,
        'discount_paise': 0,
        'service_charge_paise': 1400,
        'packaging_charge_paise': 0,
        'delivery_charge_paise': 0,
        'subtotal_paise': 56000,
        'tax_paise': 2870,
        'grand_total_paise': 60270,
        'created_at': '2026-09-06T10:00:00Z',
        'items': [
          {
            'id': 'oi-1',
            'client_id': 'item-local-1',
            'menu_item_id': 'm-01',
            'quantity': 2,
            'unit_paise': 28000,
            'total_paise': 56000,
            'is_kot_sent': true,
            'is_cancelled': false,
            'name': 'Paneer Tikka',
            'modifiers': [
              {'modifier_item_id': 'mo-1', 'name': 'Extra Mint Chutney', 'price_paise': 2000},
            ],
          },
        ],
      };
      final order = orderFromApi(json.cast<String, dynamic>(), (id) => null);
      expect(order.id, 'ord-srv-1');
      expect(order.status, OrderStatus.preparing);
      expect(order.tableNumber, 'T01');
      expect(order.serviceCharge, 14.0);
      expect(order.items.length, 1);
      final item = order.items.first;
      expect(item.quantity, 2);
      expect(item.isKOTSent, isTrue);
      expect(item.selectedModifiers.first.name, 'Extra Mint Chutney');
      // unit price falls back to unit_paise when the menu lookup misses
      expect(item.unitPrice, closeTo(280.0, 0.001));
    });
  });

  group('settings round-trip', () {
    test('settingsToApi / settingsFromApi preserve values', () {
      final s = RestaurantSettings(
        restaurantName: 'Test Resto',
        gstPercentage: 12.0,
        isGstInclusive: true,
        defaultServiceChargePercent: 8.0,
        defaultPackagingCharge: 30.0,
        defaultDeliveryCharge: 45.0,
        autoPrintKOT: false,
      );
      final json = settingsToApi(s);
      expect(json['gst_percent'], 12.0);
      expect(json['packaging_paise'], 3000);
      final back = settingsFromApi(json);
      expect(back.restaurantName, 'Test Resto');
      expect(back.gstPercentage, 12.0);
      expect(back.isGstInclusive, isTrue);
      expect(back.defaultPackagingCharge, 30.0);
      expect(back.autoPrintKOT, isFalse);
    });
  });

  group('OutboxOp persistence', () {
    test('round-trips through JSON', () async {
      SharedPreferences.setMockInitialValues({});
      final store = OutboxStore();
      final op = OutboxOp(
        id: 'op-1',
        type: 'order.create',
        payload: {'local_id': 'ord-1', 'type': 'takeaway'},
      );
      await store.save([op]);
      final loaded = await store.load();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'op-1');
      expect(loaded.first.type, 'order.create');
      expect(loaded.first.payload['local_id'], 'ord-1');
    });

    test('newOpId is unique across calls', () {
      final ids = {for (var i = 0; i < 200; i++) newOpId()};
      expect(ids.length, 200);
    });
  });
}

// Live smoke: exercises the real Flutter ApiClient against a running
// FoodPOS server (login → order → item → qty patch → KOT → pay).
// Usage: dart run tool/api_smoke.dart http://localhost:8090
// ignore_for_file: avoid_print

import 'package:food_pos/core/api/api_client.dart';
import 'package:food_pos/core/api/dto.dart';
import 'package:food_pos/models/order_model.dart';

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args.first : 'http://localhost:8080';
  final api = ApiClient(baseUrl: base);

  void check(bool cond, String label) {
    if (!cond) throw StateError('SMOKE FAILED: $label');
    print('ok: $label');
  }

  await api.login('st-01', '1234', 'out-01');
  check(api.session?.accessToken != null, 'login issues access token');

  final tables = await api.request('GET', '/api/v1/tables', query: {'outlet_id': 'out-01'});
  final tableId = (tables['tables'] as List).first['id'] as String;
  check(tableId.isNotEmpty, 'tables listed');

  final order = await api.request('POST', '/api/v1/orders', query: {'outlet_id': 'out-01'}, body: {
    'type': 'dine_in',
    'table_id': tableId,
    'client_id': 'ord-local-smoke',
    'guest_count': 2,
  }, idempotencyKey: 'smoke-order-1');
  check(order['client_id'] == 'ord-local-smoke', 'client_id echoed on order create');
  final orderId = order['id'] as String;

  final withItem = await api.request('POST', '/api/v1/orders/$orderId/items', query: {'outlet_id': 'out-01'}, body: {
    'menu_item_id': 'm-01',
    'client_id': 'item-local-smoke',
    'quantity': 1,
  });
  final item = (withItem['items'] as List).first;
  check(item['client_id'] == 'item-local-smoke', 'client_id echoed on order item');

  final qtyPatched = await api.request(
    'PATCH',
    '/api/v1/orders/$orderId/items/${item['id']}',
    query: {'outlet_id': 'out-01'},
    body: {'quantity': 3},
  );
  final line = (qtyPatched['items'] as List).first;
  check(line['quantity'] == 3, 'item quantity patched to 3');
  final dtoOrder = orderFromApi(qtyPatched.cast<String, dynamic>(), (_) => null);
  check(dtoOrder.grandTotal > 0, 'grand total computed: Rs ${dtoOrder.grandTotal}');

  final kot = await api.request('POST', '/api/v1/orders/$orderId/kot', query: {'outlet_id': 'out-01'}, body: {});
  check(kot['status'] == 'new', 'KOT fired: ${kot['kot_number']}');

  final paid = await api.request('POST', '/api/v1/orders/$orderId/pay', query: {'outlet_id': 'out-01'}, body: {
    'method': 'cash',
    'amount_received_paise': toPaise(dtoOrder.grandTotal) + 10000,
  }, idempotencyKey: 'smoke-pay-1');
  check(paid['status'] == 'completed', 'order completed');
  check(paid['change_paise'] == 10000, 'change computed: ${(paid['change_paise'] as int) / 100} Rs');
  check((paid['invoice_number'] as String).startsWith('INV-'), 'invoice issued: ${paid['invoice_number']}');

  final mapped = orderFromApi(paid.cast<String, dynamic>(), (_) => null);
  check(mapped.status == OrderStatus.completed, 'dto maps completed order');
  check(mapped.paymentMethod == 'cash', 'payment method mapped');

  await api.logout();
  api.dispose();
  print('SMOKE PASSED');
}

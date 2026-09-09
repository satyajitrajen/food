import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:food_pos/core/api/api_client.dart';
import 'package:food_pos/core/sync/outbox.dart';
import 'package:food_pos/core/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late OutboxStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = OutboxStore();
  });

  ApiClient clientWith(MockClientHandler handler) =>
      ApiClient(baseUrl: 'http://test', client: MockClient(handler));

  test('offline pushes queue FIFO, persist across restart, replay in order', () async {
    final calls = <String>[];
    var serverUp = false;
    final client = clientWith((req) async {
      if (req.url.path == '/healthz') {
        return serverUp
            ? http.Response('{"status":"ok"}', 200)
            : throw http.ClientException('offline');
      }
      if (!serverUp) throw http.ClientException('offline');
      return http.Response('{}', 200);
    });

    final engine = SyncEngine(api: client, store: store);
    await engine.initialize();
    engine.register('expense.create', (p) async {
      calls.add('expense:${p['title']}:${p['__key']}');
      return {'id': 'exp-srv-1'};
    });
    engine.register('cash.move', (p) async {
      calls.add('cash:${p['type']}:${p['__key']}');
      return null;
    });

    await engine.push('expense.create', {'title': 'Gas', 'local_id': 'exp-1'});
    await engine.push('cash.move', {'type': 'cash_in'});
    expect(engine.pending, 2);
    expect(engine.online, isFalse);

    // Restart-safety: a fresh engine over the same store sees both ops.
    final engine2 = SyncEngine(api: client, store: store);
    await engine2.initialize();
    expect(engine2.pending, 2);

    // Server comes back up; probe triggers FIFO replay.
    serverUp = true;
    engine2.register('expense.create', (p) async {
      calls.add('expense:${p['title']}:${p['__key']}');
      return {'id': 'exp-srv-1'};
    });
    engine2.register('cash.move', (p) async {
      calls.add('cash:${p['type']}:${p['__key']}');
      return null;
    });
    await engine2.probe();

    expect(engine2.online, isTrue);
    expect(engine2.pending, 0);
    expect(calls.where((c) => c.startsWith('expense:')), hasLength(1));
    expect(calls.where((c) => c.startsWith('cash:')), hasLength(1));
    // FIFO order preserved
    expect(calls.indexOf(calls.firstWhere((c) => c.startsWith('expense:'))),
        lessThan(calls.indexOf(calls.firstWhere((c) => c.startsWith('cash:')))));
    // Idempotency keys were sent as op ids
    final expenseCall = calls.firstWhere((c) => c.startsWith('expense:'));
    expect(expenseCall.contains('op-'), isTrue);
  });

  test('direct online push acks with server data and captures id map', () async {
    final client = clientWith((req) async {
      if (req.url.path == '/healthz') return http.Response('{"status":"ok"}', 200);
      return http.Response(jsonEncode({'id': 'ord-srv-9'}), 201);
    });
    final acks = <(String, Map<String, dynamic>?)>[];
    final engine = SyncEngine(
      api: client,
      store: store,
      onAck: (type, payload, data) => acks.add((type, data)),
    );
    await engine.initialize();
    engine.register('order.create', (p) async => {'id': 'ord-srv-9'});
    final ok = await engine.probe();
    expect(ok, isTrue);

    await engine.push('order.create', {'local_id': 'ord-local-1', 'type': 'takeaway'});
    expect(acks, hasLength(1));
    expect(acks.first.$2?['id'], 'ord-srv-9');
    expect(engine.idMap['ord-local-1'], 'ord-srv-9');

    // Later ops referencing the local id are remapped.
    String? seenOrderId;
    engine.register('order.add_item', (p) async {
      seenOrderId = p['order_id']?.toString();
      return null;
    });
    await engine.push('order.add_item', {'order_id': 'ord-local-1'});
    expect(seenOrderId, 'ord-srv-9');
  });

  test('permanent API rejection drops the op and surfaces the error', () async {
    var attempts = 0;
    final client = clientWith((req) async {
      attempts++;
      if (req.url.path == '/healthz') return http.Response('{"status":"ok"}', 200);
      return http.Response(
          jsonEncode({
            'error': {'code': 'invalid_state', 'message': 'nope'}
          }),
          409);
    });
    final errors = <String>[];
    final engine = SyncEngine(api: client, store: store, onError: errors.add);
    await engine.initialize();
    engine.register('item.cancel', (p) async {
      await engine.api.request(
        'POST',
        '/api/v1/orders/${p['order_id']}/items/${p['item_id']}/cancel',
        body: {'reason': p['reason']},
      );
      return null;
    });
    await engine.probe();
    await engine.push('item.cancel', {'order_id': 'x', 'item_id': 'y'});
    expect(engine.pending, 0);
    expect(errors, isNotEmpty);
    expect(attempts, 2); // health + the rejected call
  });

  test('network failure during direct push falls back to the outbox', () async {
    final client = clientWith((req) async {
      if (req.url.path == '/healthz') return http.Response('{"status":"ok"}', 200);
      throw http.ClientException('dropped');
    });
    final engine = SyncEngine(api: client, store: store);
    await engine.initialize();
    engine.register('order.pay', (p) async {
      await engine.api.request(
        'POST',
        '/api/v1/orders/${p['order_id']}/pay',
        body: {'method': 'cash'},
      );
      return null;
    });
    await engine.probe();
    expect(engine.online, isTrue);
    await engine.push('order.pay', {'order_id': 'o1'});
    expect(engine.online, isFalse);
    expect(engine.pending, 1);
  });
}

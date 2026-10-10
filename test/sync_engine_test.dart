import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:food_pos/core/api/api_client.dart';
import 'package:food_pos/core/sync/outbox.dart';
import 'package:food_pos/core/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The write path is online-only: each write goes to the server at once and
/// its caller learns whether it was saved. Nothing waits on the device.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ApiClient clientWith(MockClientHandler handler) =>
      ApiClient(baseUrl: 'http://test', client: MockClient(handler));

  /// Registers handlers that just record what was sent.
  SyncEngine engineFor(ApiClient api, List<String> calls,
      {Map<String, dynamic>? Function(String type, Map<String, dynamic> p)? reply,
      List<String>? rejected}) {
    final engine = SyncEngine(
      api: api,
      store: OutboxStore(),
      onRejected: (op, e) => rejected?.add('${op.type}:${e.code}'),
    );
    for (final type in ['order.create', 'order.add_item', 'expense.create', 'kot.fire', 'kot.status', 'purchase.create']) {
      engine.register(type, (p) async {
        calls.add('$type:${jsonEncode({...p}..remove('__key'))}');
        final res = await api.request('POST', '/api/v1/$type');
        return reply?.call(type, p) ?? (res is Map ? res.cast<String, dynamic>() : null);
      });
    }
    return engine;
  }

  test('a saved write completes with null and later writes use the server id', () async {
    final calls = <String>[];
    final api = clientWith((req) async => http.Response('{"id":"srv"}', 200));
    final engine = engineFor(api, calls, reply: (type, p) {
      if (type == 'order.create') return {'id': 'ord-srv-1'};
      if (type == 'kot.fire') return {'id': 'kot-srv-9'};
      return {'id': 'x'};
    });
    await engine.initialize();

    final created = engine.push('order.create', {'local_id': 'ord-local-1'});
    final added = engine.push('order.add_item', {'order_id': 'ord-local-1', 'menu_item_id': 'm1'});
    final fired = engine.push('kot.fire', {'order_id': 'ord-local-1', 'local_kot_id': 'kot-local-1'});
    final status = engine.push('kot.status', {'kot_id': 'kot-local-1', 'status': 'ready'});
    final purchase = engine.push('purchase.create', {
      'items': [
        {'inventory_item_id': 'inv-local'}
      ]
    });
    expect(await created, isNull);
    expect(await added, isNull);
    expect(await fired, isNull);
    expect(await status, isNull);
    expect(await purchase, isNull);

    expect(calls[1], contains('"order_id":"ord-srv-1"'));
    expect(calls[3], contains('"kot_id":"kot-srv-9"'));
    expect(engine.pending, 0);
    expect(engine.online, isTrue);
  });

  test('a refused write returns why, drops writes built on it, keeps others', () async {
    final calls = <String>[];
    final rejected = <String>[];
    final api = clientWith((req) async {
      if (req.url.path.endsWith('order.create')) {
        return http.Response('{"error":{"code":"invalid_table","message":"Table not found"}}', 400);
      }
      return http.Response('{"id":"ok"}', 200);
    });
    final engine = engineFor(api, calls, rejected: rejected);
    await engine.initialize();

    final created = engine.push('order.create', {'local_id': 'ord-local-1'});
    final dependent = engine.push('order.add_item', {'order_id': 'ord-local-1'});
    final unrelated = engine.push('expense.create', {'title': 'Gas'});

    expect(await created, 'Table not found');
    expect(await dependent, startsWith('Not saved'));
    expect(await unrelated, isNull);
    expect(rejected, ['order.create:invalid_table']);
    expect(calls.where((c) => c.startsWith('order.add_item')), isEmpty);
  });

  test('no connection: the write fails at once and nothing is kept on the device', () async {
    final calls = <String>[];
    final rejected = <String>[];
    final api = clientWith((req) async => throw http.ClientException('offline'));
    final engine = engineFor(api, calls, rejected: rejected);
    await engine.initialize();

    final result = await engine.push('expense.create', {'title': 'Gas'});
    expect(result, SyncEngine.offlineMessage);
    expect(rejected, ['expense.create:offline']);
    expect(engine.online, isFalse);
    expect(engine.pending, 0);
    expect(await OutboxStore().load(), isEmpty);
  });

  test('server errors and expired sessions are reported, not parked', () async {
    final api = clientWith((req) async => http.Response('{"error":{"code":"boom","message":"x"}}', 503));
    final engine = engineFor(api, []);
    await engine.initialize();
    expect(await engine.push('expense.create', {'title': 'Gas'}), contains('Server error'));
    expect(engine.pending, 0);
  });

  test('writes an old offline build left on the device are sent once, then removed', () async {
    SharedPreferences.setMockInitialValues({
      'foodpos.outbox.v1': jsonEncode([
        OutboxOp(id: 'op-1', type: 'expense.create', payload: {'title': 'Old'}).toJson(),
      ]),
    });
    final calls = <String>[];
    final api = clientWith((req) async =>
        req.url.path == '/healthz' ? http.Response('{"status":"ok"}', 200) : http.Response('{"id":"e1"}', 200));
    final engine = engineFor(api, calls);
    await engine.initialize();
    expect(engine.pending, 1);
    await engine.probe();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls.single, contains('Old'));
    expect(engine.pending, 0);
    expect(await OutboxStore().load(), isEmpty);
  });
}

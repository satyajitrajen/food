import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/sync/op_specs.dart';

/// Every queued op must produce exactly the request pinned in
/// contracts/sync_ops.json — the Go side decodes the same bodies with
/// DisallowUnknownFields, so a stray key here is a dropped write in prod.
void main() {
  final fixture = jsonDecode(File('contracts/sync_ops.json').readAsStringSync())
      as Map<String, dynamic>;
  final ops = (fixture['ops'] as Map).cast<String, dynamic>();

  test('every op the app sends has a contract entry', () {
    expect(knownOpTypes.toSet(), ops.keys.toSet());
  });

  for (final entry in ops.entries) {
    test('${entry.key} matches the wire contract', () {
      final spec = (entry.value as Map).cast<String, dynamic>();
      final payload = (spec['payload'] as Map).cast<String, dynamic>();
      final req = buildOpRequest(entry.key, payload);
      expect(req.method, spec['method']);
      expect(req.path, spec['path']);
      expect(req.idempotent, spec['idempotent']);
      expect(req.body, spec['body']);
    });
  }

  test('routing outlet_id never leaks into a staff body', () {
    final req = buildOpRequest('staff.create', {
      'outlet_id': 'out-routing',
      'name': 'Org-wide manager',
      'role': 'manager',
      'pin': '1234',
    });
    expect(req.body!.containsKey('outlet_id'), isFalse);
  });

  test('missing path id fails loudly instead of hitting a bad URL', () {
    expect(() => buildOpRequest('order.pay', {'method': 'cash'}), throwsArgumentError);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/models/table_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/pos_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('managers edit, re-section and delete free tables', () {
    final p = fixtureProvider();
    expect(p.loginStaff('9999'), isTrue); // manager

    expect(p.editTable('t-01', tableNumber: 'T02', seats: 4, section: 'Ground Floor'),
        'Table T02 already exists');
    expect(p.editTable('t-01', tableNumber: 'T01', seats: 0, section: 'Ground Floor'),
        'Seats must be between 1 and 50');
    expect(p.editTable('t-01', tableNumber: 'A1', seats: 6, section: 'Garden'), isNull);
    final t = p.tables.firstWhere((t) => t.id == 't-01');
    expect([t.tableNumber, t.seats, t.floor], ['A1', 6, 'Garden']);

    expect(p.deleteTable('t-02'), isNull);
    expect(p.tables.any((t) => t.id == 't-02'), isFalse);
  });

  test('a table with a running order cannot be deleted or re-statused', () {
    final p = fixtureProvider();
    expect(p.loginStaff('9999'), isTrue);
    final t = p.tables.firstWhere((t) => t.id == 't-03');
    t
      ..status = TableStatus.occupied
      ..activeOrderId = 'ord-1';
    expect(p.deleteTable('t-03'), contains('running order'));
    expect(p.changeTableStatus('t-03', TableStatus.cleaning), contains('running order'));
    expect(p.tables.any((x) => x.id == 't-03'), isTrue);
  });

  test('status changes for free tables; layout edits are manager-only', () {
    final p = fixtureProvider();
    expect(p.loginStaff('1234'), isTrue); // cashier
    expect(p.changeTableStatus('t-04', TableStatus.reserved), isNull);
    expect(p.tables.firstWhere((t) => t.id == 't-04').status, TableStatus.reserved);
    expect(p.changeTableStatus('t-04', TableStatus.occupied), isNotNull);
    expect(p.editTable('t-04', tableNumber: 'X', seats: 2, section: 'Ground Floor'),
        'Only managers can edit tables');
    expect(p.deleteTable('t-04'), 'Only managers can delete tables');
  });
}

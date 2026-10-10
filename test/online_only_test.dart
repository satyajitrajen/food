import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:food_pos/core/api/api_client.dart';
import 'package:food_pos/models/expense_model.dart';
import 'package:food_pos/providers/pos_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app keeps no data of its own: a save the server refuses (or can't
/// receive) is reported and the screen goes back to the server's data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> writes;
  late List<Map<String, dynamic>> savedExpenses;
  late bool serverUp;
  late bool refuseExpenses;

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Future<http.Response> server(http.Request req) async {
    if (!serverUp) throw http.ClientException('offline');
    final path = req.url.path;
    if (path == '/healthz') return json({'status': 'ok'});
    if (path == '/api/v1/auth/login') {
      return json({
        'access_token': 'a',
        'refresh_token': 'r',
        'staff': {'id': 'st-1', 'name': 'Priya', 'role': 'manager', 'is_active': true},
      });
    }
    if (req.method != 'GET') writes.add('${req.method} $path');
    if (path == '/api/v1/expenses' && req.method == 'POST') {
      if (refuseExpenses) {
        return json({'error': {'code': 'forbidden', 'message': 'Insufficient role'}}, 403);
      }
      final row = {'id': 'exp-srv', 'title': 'Gas', 'category': 'gas', 'amount_paise': 50000,
        'method': 'Cash', 'ts': DateTime.now().toUtc().toIso8601String()};
      savedExpenses.add(row);
      return json(row, 201);
    }
    if (path == '/api/v1/expenses') return json({'expenses': savedExpenses});
    return json({});
  }

  Future<PosProvider> signedIn() async {
    SharedPreferences.setMockInitialValues({});
    writes = [];
    savedExpenses = [];
    serverUp = true;
    refuseExpenses = false;
    final api = ApiClient(baseUrl: 'http://test', client: MockClient(server));
    final p = PosProvider(apiEnabled: true, api: api);
    await p.ready;
    expect(await p.loginStaffById('st-1', '9999'), isTrue);
    return p;
  }

  Expense gas() => Expense(
        id: 'exp-local',
        title: 'Gas',
        category: ExpenseCategory.rawMaterials,
        amount: 500,
        date: DateTime.now(),
        paymentMethod: 'Cash',
      );

  test('a saved expense is replaced by the server copy', () async {
    final p = await signedIn();
    p.addExpense(gas());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(writes, contains('POST /api/v1/expenses'));
    expect(p.expenses.map((e) => e.id), ['exp-srv']);
    p.dispose();
  });

  test('a refused expense is reported and disappears again', () async {
    final p = await signedIn();
    refuseExpenses = true;
    final errors = <String>[];
    final sub = p.saveErrors.listen(errors.add);
    p.addExpense(gas());
    expect(p.expenses, isNotEmpty); // shown while it is being saved
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(errors.single, contains('permission'));
    expect(p.expenses, isEmpty); // the server has none
    expect(p.syncRejections.first.opType, 'expense.create');
    await sub.cancel();
    p.dispose();
  });

  test('without a connection nothing is kept and the app shows offline', () async {
    final p = await signedIn();
    serverUp = false;
    final errors = <String>[];
    final sub = p.saveErrors.listen(errors.add);
    p.addExpense(gas());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(errors.single, contains('No internet'));
    expect(p.isOfflineMode, isTrue);
    expect(p.pendingSyncCount, 0);
    expect(SharedPreferences.getInstance().then((s) => s.getString('foodpos.outbox.v1')), completion(isNull));

    // Back online: everything is re-read, the unsaved expense is gone.
    serverUp = true;
    expect(await p.triggerSync(), isTrue);
    expect(p.isOfflineMode, isFalse);
    expect(p.expenses, isEmpty);
    await sub.cancel();
    p.dispose();
  });

  test('payment refused by the server leaves the bill open', () async {
    final p = await signedIn();
    final result = await p.completePayment(paymentMethod: 'Cash', amountPaid: 100);
    // No open order on this terminal: refused before anything is sent.
    expect(result.ok, isFalse);
    expect(writes.where((w) => w.contains('/pay')), isEmpty);
    p.dispose();
  });

  test('login without a connection says so instead of "wrong PIN"', () async {
    SharedPreferences.setMockInitialValues({});
    serverUp = false;
    writes = [];
    savedExpenses = [];
    final api = ApiClient(baseUrl: 'http://test', client: MockClient(server));
    final p = PosProvider(apiEnabled: true, api: api);
    await p.ready;
    expect(await p.loginStaffById('st-1', '9999'), isFalse);
    expect(p.loginError, contains('No internet'));
    p.dispose();
    unawaited(Future<void>.value());
  });
}

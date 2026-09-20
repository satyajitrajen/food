import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/auth/session_store.dart';
import 'package:food_pos/providers/pos_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SessionStore', () {
    test('round-trips the login snapshot', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SessionStore();

      expect(await store.load(), isNull);

      await store.save(StaffSessionSnapshot(
        staffId: 'st-01',
        outletId: 'out-01',
        outletName: 'Baner Outlet',
        outletTerminal: 'Counter 1',
      ));
      final snap = await store.load();
      expect(snap?.staffId, 'st-01');
      expect(snap?.outletId, 'out-01');
      expect(snap?.outletName, 'Baner Outlet');
      expect(snap?.outletTerminal, 'Counter 1');

      await store.clear();
      expect(await store.load(), isNull);
    });

    test('ignores empty and corrupt payloads', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SessionStore();

      await store.save(StaffSessionSnapshot(staffId: '', outletId: 'out-01'));
      expect(await store.load(), isNull, reason: 'empty staff id is not a session');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('foodpos.staff_session.v1', 'not-json{{{');
      expect(await store.load(), isNull);
    });

    test('snapshot holds no secrets', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SessionStore();
      await store.save(StaffSessionSnapshot(staffId: 'st-01', outletId: 'out-01'));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('foodpos.staff_session.v1') ?? '';
      expect(raw.contains('1234'), isFalse);
      expect(raw.contains('token'), isFalse);
    });
  });

  group('restoreSavedLogin', () {
    test('returns false with no saved snapshot (PIN login stays)', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = PosProvider();
      expect(await provider.restoreSavedLogin(), isFalse);
      expect(provider.currentStaff, isNull);
    });

    test('demo login persists the snapshot until logout', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = PosProvider();
      final staff = provider.currentOutletStaff.first;
      final ok = await provider.loginStaffById(staff.id, staff.pin);
      expect(ok, isTrue);

      final saved = await SessionStore().load();
      expect(saved?.staffId, staff.id);
      expect(saved?.outletId, provider.currentOutlet.id);

      provider.logout();
      // logout() clears async; allow the microtask through.
      await Future<void>.delayed(Duration.zero);
      expect(await SessionStore().load(), isNull);
    });
  });
}

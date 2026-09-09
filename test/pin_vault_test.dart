import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/auth/pin_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('remembers server-verified PINs as salted hashes (never plaintext)', () async {
    SharedPreferences.setMockInitialValues({});
    final vault = PinVault();

    await vault.remember(staffId: 'st-01', name: 'Rahul', role: 'cashier', pin: '1234');

    final staff = await vault.verifyStaff('st-01', '1234');
    expect(staff?.id, 'st-01');
    expect(staff?.role.name, 'cashier');
    expect(await vault.verifyStaff('st-01', '0000'), isNull, reason: 'wrong PIN must fail');
    expect(await vault.verifyStaff('st-99', '1234'), isNull, reason: 'unknown staff must fail');

    // The persisted value must not contain the plaintext PIN.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('foodpos.pinvault') ?? '';
    expect(raw.contains('1234'), isFalse, reason: 'plaintext PIN leaked into storage');
  });

  test('verifyAnyManager only authorizes cached manager/admin hashes', () async {
    SharedPreferences.setMockInitialValues({});
    final vault = PinVault();

    await vault.remember(staffId: 'st-01', name: 'Rahul', role: 'cashier', pin: '1234');
    expect(await vault.verifyAnyManager('1234'), isNull, reason: 'cashier PIN is not a manager gate');

    await vault.remember(staffId: 'st-02', name: 'Priya', role: 'manager', pin: '9999');
    final manager = await vault.verifyAnyManager('9999');
    expect(manager?.id, 'st-02');
    expect(await vault.verifyAnyManager('1111'), isNull);
  });

  test('re-authentication rotates the hash (PIN change support)', () async {
    SharedPreferences.setMockInitialValues({});
    final vault = PinVault();

    await vault.remember(staffId: 'st-03', name: 'Amit', role: 'waiter', pin: '1111');
    await vault.remember(staffId: 'st-03', name: 'Amit', role: 'waiter', pin: '2222');

    expect(await vault.verifyStaff('st-03', '1111'), isNull, reason: 'old PIN must stop working');
    expect((await vault.verifyStaff('st-03', '2222'))?.id, 'st-03');
  });
}

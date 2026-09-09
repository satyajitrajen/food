import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/auth/tenant.dart';

void main() {
  const secret = 'test-license-secret';
  String payload({
    String status = 'active',
    String? validUntil,
    int grace = 7,
  }) =>
      jsonEncode({
        'status': status,
        'valid_until': validUntil ?? DateTime.now().add(const Duration(days: 10)).toIso8601String(),
        'grace_days': grace,
      });

  test('verifies a valid entitlement token and parses it', () {
    final token = entitlementTokenForTest(payload(), secret);
    final snap = verifyEntitlementToken(token, secret: secret);
    expect(snap, isNotNull);
    expect(snap!.status, 'active');
    expect(snap.isActive, isTrue);
    expect(snap.tokenVerified, isTrue);
  });

  test('rejects tampered tokens and wrong secrets', () {
    final token = entitlementTokenForTest(payload(), secret);
    expect(verifyEntitlementToken('$token.extra', secret: secret), isNull);
    expect(verifyEntitlementToken(token, secret: 'wrong'), isNull);
    expect(verifyEntitlementToken('bogus', secret: secret), isNull);
  });

  test('an expired or suspended snapshot is inactive', () {
    final expired = EntitlementSnapshot(
      status: 'active',
      validUntil: DateTime.now().subtract(const Duration(days: 1)),
      graceDays: 7,
      token: '',
      tokenVerified: false,
    );
    expect(expired.isActive, isFalse);
    final suspended = EntitlementSnapshot(
      status: 'suspended',
      validUntil: DateTime.now().add(const Duration(days: 5)),
      graceDays: 0,
      token: '',
      tokenVerified: false,
    );
    expect(suspended.isActive, isFalse);
    expect(suspended.daysLeft, 5);
  });

  test('falls back to the server payload when no secret is set', () {
    final snap = entitlementFromServer({
      'status': 'trial',
      'valid_until': DateTime.now().add(const Duration(days: 14)).toIso8601String(),
      'grace_days': 7,
    }, null);
    expect(snap.status, 'trial');
    expect(snap.isActive, isTrue);
    expect(snap.tokenVerified, isFalse);
  });
}

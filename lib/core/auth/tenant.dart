import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// License secret used to verify server-issued `entitlement_token` values
/// offline. Pass via --dart-define=FOODPOS_LICENSE_SECRET=... When unset, the
/// terminal trusts the entitlement object it received over HTTPS (still
/// enforced server-side by 402s).
const String kLicenseSecret =
    String.fromEnvironment('FOODPOS_LICENSE_SECRET', defaultValue: '');

/// Bound tenant on this terminal (org code + org id).
class TenantInfo {
  final String orgCode;
  final String orgId;
  final String orgName;

  TenantInfo({required this.orgCode, required this.orgId, required this.orgName});

  Map<String, dynamic> toJson() =>
      {'org_code': orgCode, 'org_id': orgId, 'org_name': orgName};

  factory TenantInfo.fromJson(Map<String, dynamic> j) => TenantInfo(
        orgCode: (j['org_code'] ?? '').toString(),
        orgId: (j['org_id'] ?? '').toString(),
        orgName: (j['org_name'] ?? '').toString(),
      );
}

/// Offline entitlement: cached from the login response and re-checked against
/// the local clock. `validUntil` already includes the server grace days.
class EntitlementSnapshot {
  final String status; // trial | active | past_due | suspended | expired | cancelled
  final DateTime validUntil;
  final int graceDays;
  final String token;
  final bool tokenVerified;

  EntitlementSnapshot({
    required this.status,
    required this.validUntil,
    required this.graceDays,
    required this.token,
    required this.tokenVerified,
  });

  bool get isPaidStatus => status == 'trial' || status == 'active';

  /// Active = paid status and still within the (grace-extended) window.
  bool get isActive => isPaidStatus && !DateTime.now().isAfter(validUntil);

  int get daysLeft {
    final diff = validUntil.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inMinutes / (24 * 60)).ceil();
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'valid_until': validUntil.toUtc().toIso8601String(),
        'grace_days': graceDays,
        'token': token,
        'token_verified': tokenVerified,
      };

  factory EntitlementSnapshot.fromJson(Map<String, dynamic> j) =>
      EntitlementSnapshot(
        status: (j['status'] ?? '').toString(),
        validUntil: DateTime.tryParse((j['valid_until'] ?? '').toString()) ??
            DateTime.now().add(const Duration(days: 1)),
        graceDays: (j['grace_days'] as num?)?.toInt() ?? 7,
        token: (j['token'] ?? '').toString(),
        tokenVerified: j['token_verified'] == true,
      );
}

/// Persists the terminal tenant binding + last entitlement.
class TenantStore {
  static const _tenantKey = 'foodpos.tenant.v1';
  static const _entKey = 'foodpos.entitlement.v1';

  final Future<SharedPreferences> _prefs;

  TenantStore([Future<SharedPreferences>? prefs])
      : _prefs = prefs ?? SharedPreferences.getInstance();

  Future<TenantInfo?> load() async {
    final raw = (await _prefs).getString(_tenantKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return TenantInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(TenantInfo t) async =>
      (await _prefs).setString(_tenantKey, jsonEncode(t.toJson()));

  Future<void> clear() async => (await _prefs).remove(_tenantKey);

  Future<EntitlementSnapshot?> loadEntitlement() async {
    final raw = (await _prefs).getString(_entKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return EntitlementSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveEntitlement(EntitlementSnapshot e) async =>
      (await _prefs).setString(_entKey, jsonEncode(e.toJson()));

  Future<void> clearEntitlement() async => (await _prefs).remove(_entKey);
}

// ---- entitlement_token verification (HMAC-SHA256) ----
// Token shape from the backend: base64url(payloadJSON).base64url(hmac)

Uint8List _hmacSha256Bytes(List<int> key, List<int> data) =>
    Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);

String _b64urlEnc(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Verifies a server entitlement token and returns the parsed snapshot when
/// the signature checks out. Pass [secret] for tests; defaults to the
/// dart-define value. Returns null when the secret is unset (callers fall back
/// to trusting the login payload) or on any tamper/format error.
EntitlementSnapshot? verifyEntitlementToken(
  String token, {
  String secret = kLicenseSecret,
}) {
  if (secret.isEmpty || token.isEmpty) return null;
  final parts = token.split('.');
  if (parts.length != 2) return null;
  String unescapeUrl64(String part) {
    var s = part.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return s;
  }

  final String payloadJson;
  try {
    payloadJson = utf8.decode(base64.decode(unescapeUrl64(parts[0])));
  } catch (_) {
    return null;
  }
  final want = base64.decode(unescapeUrl64(parts[1]));
  final mac = _hmacSha256Bytes(utf8.encode(secret), utf8.encode(payloadJson));
  if (want.length != mac.length) return null;
  var diff = 0;
  for (var i = 0; i < want.length; i++) {
    diff |= want[i] ^ mac[i];
  }
  if (diff != 0) return null;

  try {
    final map = jsonDecode(payloadJson) as Map<String, dynamic>;
    return EntitlementSnapshot(
      status: (map['status'] ?? '').toString(),
      validUntil: DateTime.tryParse((map['valid_until'] ?? '').toString()) ??
          DateTime.now().add(const Duration(days: 1)),
      graceDays: (map['grace_days'] as num?)?.toInt() ?? 7,
      token: token,
      tokenVerified: true,
    );
  } catch (_) {
    return null;
  }
}

/// Builds the snapshot from a login payload (server truth) + optional token.
EntitlementSnapshot entitlementFromServer(
  Map<String, dynamic>? entitlement,
  String? token,
) {
  final verified = verifyEntitlementToken(token ?? '');
  if (verified != null) return verified;
  return EntitlementSnapshot(
    status: (entitlement?['status'] ?? 'active').toString(),
    validUntil: DateTime.tryParse(
            (entitlement?['valid_until'] ?? '').toString()) ??
        DateTime.now().add(const Duration(days: 7)),
    graceDays: (entitlement?['grace_days'] as num?)?.toInt() ?? 7,
    token: token ?? '',
    tokenVerified: token != null && token.isNotEmpty && kLicenseSecret.isEmpty,
  );
}

/// Test helper: builds a token exactly like the Go backend does.
String entitlementTokenForTest(String payloadJson, String secret) {
  final mac = _hmacSha256Bytes(utf8.encode(secret), utf8.encode(payloadJson));
  return '${_b64urlEnc(utf8.encode(payloadJson))}.${_b64urlEnc(mac)}';
}

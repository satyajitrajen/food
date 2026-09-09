import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/staff_model.dart';

/// Offline PIN vault.
///
/// Replaces the plaintext demo PINs: whenever a PIN is *verified by the
/// server* (login or manager gate), the terminal caches a salted SHA-256
/// hash — never the PIN itself. Offline logins / manager gates then verify
/// against these cached hashes, so only staff who have authenticated on this
/// device at least once can work offline. New PINs still require the server.
class PinVault {
  static const _key = 'foodpos.pinvault';

  final Future<SharedPreferences> _prefs;

  PinVault([Future<SharedPreferences>? prefs]) : _prefs = prefs ?? SharedPreferences.getInstance();

  /// Computes hash = sha256("foodpos:$staffId:$salt:$pin").
  static String _hash(String staffId, String salt, String pin) =>
      sha256.convert(utf8.encode('foodpos:$staffId:$salt:$pin')).toString();

  /// Called after a SERVER-verified PIN (login or manager gate).
  Future<void> remember({
    required String staffId,
    required String name,
    required String role,
    required String pin,
  }) async {
    if (staffId.isEmpty || pin.isEmpty) return;
    final prefs = await _prefs;
    final all = _readAll(prefs);
    // Keep the salt when the staff re- authenticates (PIN changes rotate it).
    final salt = all[staffId]?['salt'] as String? ?? _randomSalt();
    all[staffId] = {
      'id': staffId,
      'name': name,
      'role': role,
      'salt': salt,
      'hash': _hash(staffId, salt, pin),
    };
    await prefs.setString(_key, jsonEncode(all));
  }

  /// Offline login: verifies staffId + pin against the cached hash and
  /// returns the cached staff identity (null when unknown).
  Future<Staff?> verifyStaff(String staffId, String pin) async {
    final prefs = await _prefs;
    final e = _readAll(prefs)[staffId];
    if (e == null) return null;
    if (_hash(staffId, e['salt'] as String, pin) != e['hash']) return null;
    return _staffOf(e);
  }

  /// Offline manager gate: returns the first cached manager/admin whose PIN
  /// verifies, so privileged actions stay gated with no server.
  Future<Staff?> verifyAnyManager(String pin) async {
    if (pin.isEmpty) return null;
    final prefs = await _prefs;
    for (final e in _readAll(prefs).values) {
      final role = e['role']?.toString() ?? '';
      if (role != 'manager' && role != 'admin') continue;
      final id = e['id'].toString();
      if (_hash(id, e['salt'] as String, pin) != e['hash']) continue;
      return _staffOf(e);
    }
    return null;
  }

  static Staff _staffOf(Map<String, dynamic> e) => Staff(
        id: e['id'].toString(),
        name: e['name']?.toString() ?? 'Staff',
        role: StaffRole.values.firstWhere(
          (r) => r.name == e['role'],
          orElse: () => StaffRole.waiter,
        ),
        pin: '',
        avatarUrl: '',
        mobile: '',
      );

  Map<String, dynamic> _readAll(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (_) {
      return {};
    }
  }

  static String _randomSalt() {
    final rnd = Random.secure();
    return sha256.convert(List<int>.generate(16, (_) => rnd.nextInt(256))).toString().substring(0, 16);
  }
}

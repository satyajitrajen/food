import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted login snapshot: who is signed in on this device and on which
/// outlet. This is what keeps staff logged in across app restarts — it is
/// cleared only on explicit logout (or org rebind).
///
/// No secrets live here: the API tokens stay in `OutboxStore` and PINs are
/// never stored (only salted hashes in `PinVault`). The snapshot alone
/// authorizes nothing; online restores re-validate via token refresh and
/// offline restores rely on a previously server-verified vault entry.
class StaffSessionSnapshot {
  final String staffId;
  final String outletId;
  final String outletName;
  final String outletTerminal;

  StaffSessionSnapshot({
    required this.staffId,
    required this.outletId,
    this.outletName = '',
    this.outletTerminal = '',
  });

  Map<String, dynamic> toJson() => {
        'staff_id': staffId,
        'outlet_id': outletId,
        'outlet_name': outletName,
        'outlet_terminal': outletTerminal,
      };

  factory StaffSessionSnapshot.fromJson(Map<String, dynamic> j) =>
      StaffSessionSnapshot(
        staffId: (j['staff_id'] ?? '').toString(),
        outletId: (j['outlet_id'] ?? '').toString(),
        outletName: (j['outlet_name'] ?? '').toString(),
        outletTerminal: (j['outlet_terminal'] ?? '').toString(),
      );
}

class SessionStore {
  static const _key = 'foodpos.staff_session.v1';

  final Future<SharedPreferences> _prefs;

  SessionStore([Future<SharedPreferences>? prefs])
      : _prefs = prefs ?? SharedPreferences.getInstance();

  Future<void> save(StaffSessionSnapshot snap) async {
    if (snap.staffId.isEmpty) return;
    (await _prefs).setString(_key, jsonEncode(snap.toJson()));
  }

  Future<StaffSessionSnapshot?> load() async {
    final raw = (await _prefs).getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final snap = StaffSessionSnapshot.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      if (snap.staffId.isEmpty) return null;
      return snap;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async => (await _prefs).remove(_key);
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A queued write operation. `id` doubles as the Idempotency-Key sent to the
/// server so replays after crashes never double-apply.
class OutboxOp {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  OutboxOp({
    required this.id,
    required this.type,
    required this.payload,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
      };

  static OutboxOp fromJson(Map<String, dynamic> j) => OutboxOp(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? {},
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );
}

/// Device storage for the API session tokens. It also reads (once) any
/// writes an older offline build left queued on the device, so they can be
/// sent before that queue is removed; the app keeps no write queue itself.
class OutboxStore {
  static const _storageKey = 'foodpos.outbox.v1';
  static const _sessionKey = 'foodpos.session.v1';
  static const _idMapKey = 'foodpos.idmap.v1';

  Future<List<OutboxOp>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => OutboxOp.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<OutboxOp> ops) async {
    final prefs = await SharedPreferences.getInstance();
    if (ops.isEmpty) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(
        _storageKey,
        jsonEncode(ops.map((o) => o.toJson()).toList()),
      );
    }
  }

  /// Local→server id map, persisted so ops queued before a restart that
  /// reference a since-acked local id still resolve to the server id.
  Future<Map<String, String>> loadIdMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_idMapKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveIdMap(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idMapKey, jsonEncode(map));
  }

  /// Removes the legacy on-device write queue and its id map.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_idMapKey);
  }

  Future<void> saveSession(String? accessToken, String? refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    if (accessToken == null || accessToken.isEmpty) {
      await prefs.remove(_sessionKey);
    } else {
      await prefs.setString(_sessionKey,
          jsonEncode({'access': accessToken, 'refresh': refreshToken ?? ''}));
    }
  }

  Future<(String, String)?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map;
      final access = (m['access'] ?? '').toString();
      if (access.isEmpty) return null;
      return (access, (m['refresh'] ?? '').toString());
    } catch (_) {
      return null;
    }
  }
}

/// Collision-resistant idempotency/operation id without external deps.
String newOpId() {
  final ms = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rand = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      (OutboxStore).hashCode.toRadixString(36);
  return 'op-$ms-${rand.substring(rand.length >= 6 ? rand.length - 6 : 0)}-${_counter++}';
}

int _counter = 0;

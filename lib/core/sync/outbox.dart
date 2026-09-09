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

/// FIFO write-ahead queue persisted in SharedPreferences so pending writes
/// survive an app restart (PRD FR-X1).
class OutboxStore {
  static const _storageKey = 'foodpos.outbox.v1';
  static const _sessionKey = 'foodpos.session.v1';

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

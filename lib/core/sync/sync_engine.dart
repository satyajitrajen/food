import 'dart:async';

import '../api/api_client.dart';
import '../payments/billing_policy.dart';
import 'outbox.dart';

typedef OpHandler = Future<Map<String, dynamic>?> Function(
    Map<String, dynamic> payload);

/// Online-only write path for every server mutation.
///
/// Writes are sent to the server straight away, one at a time in the order
/// they were made, and each caller gets the outcome: `null` when the server
/// saved it, otherwise a message to show. Nothing is queued on the device:
/// a write that can't reach the server fails right away instead of waiting
/// in a local queue, so the server is always the only copy of the data.
///
/// Order still matters within a session: `order.add_item` must not reach the
/// server before the `order.create` it depends on, and its local id is
/// rewritten to the server id the create returned.
class SyncEngine {
  final ApiClient api;
  final OutboxStore store;

  /// Fires on online/offline transitions and in-flight count changes.
  final void Function(bool online, int pending)? onChanged;

  /// Fires when the server saved a write.
  final void Function(String type, Map<String, dynamic> payload,
      Map<String, dynamic>? data)? onAck;

  /// Fires when a write was not saved (refused or no connection), so the
  /// owner can undo what it showed and re-read server truth.
  final void Function(OutboxOp op, ApiException error)? onRejected;

  /// Fires when the server is reachable again after being offline.
  final void Function()? onReconnect;

  final Map<String, OpHandler> _handlers = {};
  final List<OutboxOp> _queue = [];
  final Map<String, String> _idMap = {};
  final Map<String, Completer<String?>> _waiters = {};
  bool _online = false;
  bool _draining = false;
  bool _initialized = false;
  bool _legacy = false;
  Timer? _probeTimer;
  DateTime? _lastSyncAt;

  SyncEngine({
    required this.api,
    required this.store,
    this.onChanged,
    this.onAck,
    this.onRejected,
    this.onReconnect,
  });

  bool get online => _online;

  /// Writes sent but not answered yet.
  int get pending => _queue.length;
  Map<String, String> get idMap => _idMap;

  /// When the server last saved a write.
  DateTime? get lastSyncAt => _lastSyncAt;

  void register(String type, OpHandler handler) => _handlers[type] = handler;

  /// Resolves a local id to the server id the create returned.
  String resolveId(String id) => _idMap[id] ?? id;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final saved = await store.loadSession();
    if (saved != null) {
      api.session = AuthSession(accessToken: saved.$1, refreshToken: saved.$2);
    }
    // Writes left queued on this device by the old offline build are sent
    // once, then the on-device queue is gone for good.
    final leftovers = await store.load();
    if (leftovers.isNotEmpty) {
      _legacy = true;
      _queue.addAll(leftovers);
      _idMap.addAll(await store.loadIdMap());
    } else {
      await store.clear();
    }
    _emit();
  }

  /// Checks the server every few seconds while offline (so the app unlocks
  /// itself as soon as the connection is back) and every [onlineEvery] while
  /// online (so a dropped connection is noticed before someone tries to save).
  void startProbing({
    Duration every = const Duration(seconds: 5),
    int onlineEvery = 3,
  }) {
    _probeTimer?.cancel();
    var tick = 0;
    _probeTimer = Timer.periodic(every, (_) {
      tick++;
      if (_probing || _draining) return;
      if (!_online || tick % onlineEvery == 0) probe();
    });
  }

  bool _probing = false;
  int _misses = 0;

  void dispose() {
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  Future<bool> probe() async {
    _probing = true;
    final bool ok;
    try {
      ok = await api.health();
    } finally {
      _probing = false;
    }
    // One slow answer on mobile data is not "offline": two misses in a row
    // are. (A save that can't reach the server switches at once.)
    _misses = ok ? 0 : _misses + 1;
    if (ok || !_online || _misses >= 2) _setOnline(ok);
    if (ok && _queue.isNotEmpty) unawaited(_drain());
    return ok;
  }

  /// Sends one write and completes with `null` once the server saved it, or
  /// with a message saying why it was not saved.
  Future<String?> push(String type, Map<String, dynamic> payload) {
    final op = OutboxOp(id: newOpId(), type: type, payload: payload);
    final done = Completer<String?>();
    _waiters[op.id] = done;
    _queue.add(op);
    _emit();
    unawaited(_drain());
    return done.future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final op = _queue.first;
        try {
          final data = await _execute(op.type, op.payload, op.id);
          _captureIdMap(op.payload, data);
          _queue.removeAt(0);
          _lastSyncAt = DateTime.now();
          _setOnline(true);
          _emit();
          onAck?.call(op.type, op.payload, data);
          _complete(op.id, null);
        } on NetworkException {
          // No connection: nothing in flight can be saved. Fail all of it so
          // the screens undo what they showed.
          _setOnline(false);
          final failed = List<OutboxOp>.from(_queue);
          _queue.clear();
          _emit();
          for (final f in failed) {
            onRejected?.call(f, ApiException(0, 'offline', offlineMessage));
            _complete(f.id, offlineMessage);
          }
        } on ApiException catch (e) {
          _queue.removeAt(0);
          final message = describeWriteError(e);
          // Writes made on top of this one (same order / record) can't be
          // right either.
          final dependents = _queue.where((o) => _dependsOn(o, op)).toList();
          _queue.removeWhere(dependents.contains);
          _emit();
          onRejected?.call(op, e);
          _complete(op.id, message);
          for (final d in dependents) {
            _complete(d.id, 'An earlier change to this record failed ($message)');
          }
        }
      }
    } finally {
      _draining = false;
      if (_legacy && _queue.isEmpty) {
        _legacy = false;
        unawaited(store.clear());
      }
    }
  }

  static const offlineMessage = 'No internet connection.';

  /// A short, user-facing reason for a refused write.
  static String describeWriteError(ApiException e) {
    if (e.status == 401) return 'Your session expired. Sign in again.';
    if (e.status == 402 || e.code == 'subscription_expired') {
      return inAppBillingAllowed
          ? 'Subscription expired. Renew to keep saving.'
          : 'Subscription expired. Changes cannot be saved.';
    }
    if (e.status == 403 && e.code == 'forbidden') {
      return "You don't have permission to do this.";
    }
    if (e.status >= 500) return 'Server error, please try again.';
    if (e.status == 429) return 'Too many requests. Wait a moment and try again.';
    return e.message.isNotEmpty ? e.message : 'Error ${e.status}.';
  }

  static const _refKeys = {
    'order_id', 'item_id', 'kot_id', 'customer_id', 'expense_id',
    'supplier_id', 'table_id', 'inventory_item_id', 'menu_item_id',
    'purchase_id', 'staff_id',
  };

  /// Whether [later] refers to the record [failed] created or changed.
  bool _dependsOn(OutboxOp later, OutboxOp failed) {
    final ids = <String>{
      for (final k in [..._refKeys, 'local_id', 'local_item_id', 'local_kot_id'])
        if (failed.payload[k] is String) failed.payload[k] as String,
    };
    if (ids.isEmpty) return false;
    for (final k in _refKeys) {
      final v = later.payload[k];
      if (v is String && ids.contains(v)) return true;
    }
    return false;
  }

  /// Records local→server id mappings so later writes referencing a local
  /// id are rewritten to the server id before they are sent.
  void _captureIdMap(Map<String, dynamic> payload, Map<String, dynamic>? data) {
    if (data == null) return;
    final server = data['id'];
    // local_kot_id: the KOT the screen showed before the server numbered it.
    for (final key in const ['local_id', 'local_kot_id']) {
      final local = payload[key];
      if (local is String && local.isNotEmpty && server is String && server.isNotEmpty) {
        _idMap[local] = server;
      }
    }
    final localItem = payload['local_item_id'];
    if (localItem is String && localItem.isNotEmpty) {
      String? serverItem = data['item_id'] is String ? data['item_id'] as String : null;
      if (serverItem == null && data['items'] is List) {
        for (final it in data['items'] as List) {
          if (it is Map && it['client_id'] == localItem && it['id'] is String) {
            serverItem = it['id'] as String;
            break;
          }
        }
      }
      if (serverItem != null && serverItem.isNotEmpty) _idMap[localItem] = serverItem;
    }
  }

  Future<Map<String, dynamic>?> _execute(
      String type, Map<String, dynamic> payload, String key) async {
    final handler = _handlers[type];
    if (handler == null) {
      throw ApiException(400, 'no_handler', 'No handler registered for $type');
    }
    final wire = _remap(payload);
    wire['__key'] = key;
    return await handler(wire);
  }

  /// Rewrites local ids (top level and inside list items, e.g. purchase
  /// lines) to the server ids.
  dynamic _remapValue(String? key, dynamic v) {
    if (v is String && key != null && _refKeys.contains(key)) return _idMap[v] ?? v;
    if (v is Map) return _remap(v.cast<String, dynamic>());
    if (v is List) return [for (final e in v) _remapValue(null, e)];
    return v;
  }

  Map<String, dynamic> _remap(Map<String, dynamic> payload) => {
        for (final e in payload.entries) e.key: _remapValue(e.key, e.value),
      };

  void _complete(String opId, String? error) {
    final c = _waiters.remove(opId);
    if (c != null && !c.isCompleted) c.complete(error);
  }

  void _setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    _emit();
    if (value) onReconnect?.call();
  }

  void _emit() => onChanged?.call(_online, _queue.length);
}

/// A write the server did not save (shown in the connection panel).
class SyncRejection {
  final String opType;
  final String message;
  final DateTime at;
  const SyncRejection(this.opType, this.message, this.at);
}

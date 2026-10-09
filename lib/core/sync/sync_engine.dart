import 'dart:async';

import '../api/api_client.dart';
import 'outbox.dart';

enum SyncStatus { offline, online }

typedef OpHandler = Future<Map<String, dynamic>?> Function(
    Map<String, dynamic> payload);

/// Single FIFO write path for every server mutation.
///
/// Every push is appended to the persisted outbox and drained in order, online
/// or offline. Ordering matters: `order.add_item` must not reach the server
/// before the `order.create` it depends on has been acknowledged and its
/// local id remapped to the server id.
class SyncEngine {
  final ApiClient api;
  final OutboxStore store;

  /// Fires on online/offline transitions and pending-count changes.
  final void Function(bool online, int pending)? onChanged;

  /// Fires when a queued op is confirmed by the server.
  final void Function(String type, Map<String, dynamic> payload,
      Map<String, dynamic>? data)? onAck;

  /// Fires when the server permanently rejects an op (4xx). Server truth
  /// wins; the op is dropped, never silently.
  final void Function(String message)? onError;

  /// Like [onError] but with the rejected op, so the owner can roll back the
  /// optimistic local state it applied for that op.
  final void Function(OutboxOp op, ApiException error)? onRejected;

  final Map<String, OpHandler> _handlers = {};
  final List<OutboxOp> _queue = [];
  final Map<String, String> _idMap = {};
  final Map<String, Completer<void>> _waiters = {};
  bool _online = false;
  bool _replaying = false;
  bool _forceOffline = false;
  bool _initialized = false;
  bool _blocked = false;
  Timer? _retryTimer;
  DateTime? _lastSyncAt;
  String? _blockedReason;

  SyncEngine({
    required this.api,
    required this.store,
    this.onChanged,
    this.onAck,
    this.onError,
    this.onRejected,
  });

  bool get online => _online;
  int get pending => _queue.length;
  List<OutboxOp> get queuedOps => List.unmodifiable(_queue);
  Map<String, String> get idMap => _idMap;

  /// When the outbox last drained an op successfully.
  DateTime? get lastSyncAt => _lastSyncAt;

  /// Set while the queue is parked on an auth/subscription problem that a
  /// retry cannot fix by itself (re-login or renewal needed).
  String? get blockedReason => _blockedReason;

  void register(String type, OpHandler handler) => _handlers[type] = handler;

  /// Resolves a local id to the server id once its create op was acked.
  String resolveId(String id) => _idMap[id] ?? id;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _queue.addAll(await store.load());
    _idMap.addAll(await store.loadIdMap());
    final saved = await store.loadSession();
    if (saved != null) {
      api.session = AuthSession(
        accessToken: saved.$1,
        refreshToken: saved.$2,
      );
    }
    _emit();
  }

  /// Periodically re-probes the server while writes are pending or the
  /// device is offline, so a terminal that booted offline drains its outbox
  /// on its own once connectivity returns.
  void startAutoRetry({Duration every = const Duration(seconds: 30)}) {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(every, (_) {
      if (_forceOffline || _replaying) return;
      if (!_online || _queue.isNotEmpty) {
        _blocked = false;
        probe();
      }
    });
  }

  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<bool> probe() async {
    if (_forceOffline) {
      _setOnline(false);
      return false;
    }
    final ok = await api.health();
    _setOnline(ok);
    if (ok && _queue.isNotEmpty) {
      _blocked = false;
      await replay();
    }
    return ok;
  }

  void setForceOffline(bool value) {
    _forceOffline = value;
    if (value) _setOnline(false);
  }

  /// Fire-and-forget write path: the caller has already applied the change
  /// locally. The op is persisted, then the queue drains in FIFO order. The
  /// returned future completes once this op is acked or rejected, or right
  /// away when the device is offline (the op stays queued).
  Future<void> push(String type, Map<String, dynamic> payload) async {
    final op = _enqueue(type, payload);
    if (!_online || _blocked) {
      return;
    }
    final done = Completer<void>();
    _waiters[op.id] = done;
    unawaited(replay());
    await done.future;
  }

  Future<void> replay() async {
    if (_replaying || !_online || _queue.isEmpty) {
      if (!_online || _blocked) _releaseWaiters();
      return;
    }
    _replaying = true;
    try {
      while (_queue.isNotEmpty && _online && !_blocked) {
        final op = _queue.first;
        try {
          final data = await _execute(op.type, op.payload, op.id);
          _captureIdMap(op.payload, data);
          _queue.removeAt(0);
          _lastSyncAt = DateTime.now();
          _blockedReason = null;
          await store.save(_queue);
          _emit();
          onAck?.call(op.type, op.payload, data);
          _complete(op.id);
        } on NetworkException {
          _setOnline(false);
          break;
        } on ApiException catch (e) {
          if (_isTransient(e)) {
            // Server-side trouble or an expired session/subscription: keep the
            // op (and everything behind it) for a later retry instead of
            // dropping a sale.
            _blocked = true;
            _blockedReason = e.message;
            _emit();
            onError?.call(e.message);
            break;
          }
          _queue.removeAt(0);
          await store.save(_queue);
          _emit();
          onError?.call(e.message);
          onRejected?.call(op, e);
          _complete(op.id);
        }
      }
    } finally {
      _replaying = false;
      _releaseWaiters();
    }
  }

  /// 401/402/403 need a human (re-login, renewal) and 408/409-in-progress,
  /// 429 and 5xx clear up on their own; none of them mean "this op is wrong".
  bool _isTransient(ApiException e) =>
      e.status == 401 ||
      e.status == 402 ||
      e.status == 403 && e.code == 'subscription_expired' ||
      e.status == 408 ||
      e.status == 429 ||
      (e.status == 409 && e.code == 'in_progress') ||
      e.status >= 500;

  /// Records local→server id mappings so later queued ops referencing local
  /// ids are rewritten to server ids before executing.
  void _captureIdMap(Map<String, dynamic> payload, Map<String, dynamic>? data) {
    if (data == null) return;
    var changed = false;
    final local = payload['local_id'];
    final server = data['id'];
    if (local is String && local.isNotEmpty && server is String && server.isNotEmpty) {
      _idMap[local] = server;
      changed = true;
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
      if (serverItem != null && serverItem.isNotEmpty) {
        _idMap[localItem] = serverItem;
        changed = true;
      }
    }
    if (changed) {
      _trimIdMap();
      store.saveIdMap(_idMap);
    }
  }

  void _trimIdMap() {
    const maxEntries = 2000;
    if (_idMap.length <= maxEntries) return;
    final drop = _idMap.keys.take(_idMap.length - maxEntries).toList();
    for (final k in drop) {
      _idMap.remove(k);
    }
  }

  Future<Map<String, dynamic>?> _execute(
      String type, Map<String, dynamic> payload, String key) async {
    final handler = _handlers[type];
    if (handler == null) {
      throw ApiException(400, 'no_handler', 'No handler registered for $type');
    }
    final wire = _remapPayload(Map<String, dynamic>.from(payload));
    wire['__key'] = key;
    return await handler(wire);
  }

  Map<String, dynamic> _remapPayload(Map<String, dynamic> payload) {
    const remapKeys = {
      'order_id', 'item_id', 'kot_id', 'customer_id', 'expense_id',
      'supplier_id', 'table_id', 'from_table_id', 'to_table_id',
      'primary_table_id', 'secondary_table_id', 'inventory_item_id',
      'menu_item_id', 'purchase_id', 'staff_id',
    };
    final out = <String, dynamic>{};
    payload.forEach((k, v) {
      if (remapKeys.contains(k) && v is String) {
        out[k] = _idMap[v] ?? v;
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  OutboxOp _enqueue(String type, Map<String, dynamic> payload) {
    final op = OutboxOp(id: newOpId(), type: type, payload: payload);
    _queue.add(op);
    store.save(_queue);
    _emit();
    return op;
  }

  void _complete(String opId) {
    final c = _waiters.remove(opId);
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Unblocks callers awaiting ops that stay queued (offline/blocked).
  void _releaseWaiters() {
    if (_waiters.isEmpty) return;
    final pendingIds = _queue.map((o) => o.id).toSet();
    final stuck = !_online || _blocked;
    for (final id in _waiters.keys.toList()) {
      if (stuck || !pendingIds.contains(id)) _complete(id);
    }
  }

  void _setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    _emit();
  }

  void _emit() => onChanged?.call(_online, _queue.length);
}

/// A write the server refused for good (shown in the sync panel).
class SyncRejection {
  final String opType;
  final String message;
  final DateTime at;
  const SyncRejection(this.opType, this.message, this.at);
}

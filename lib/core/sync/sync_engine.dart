import '../api/api_client.dart';
import 'outbox.dart';

enum SyncStatus { offline, online }

typedef OpHandler = Future<Map<String, dynamic>?> Function(
    Map<String, dynamic> payload);

class SyncEngine {
  final ApiClient api;
  final OutboxStore store;

  /// Fires on online/offline transitions and pending-count changes.
  final void Function(bool online, int pending)? onChanged;

  /// Fires when a queued op is confirmed by the server (replay or direct).
  final void Function(String type, Map<String, dynamic> payload,
      Map<String, dynamic>? data)? onAck;

  /// Fires when the server permanently rejects an op (4xx). Server truth
  /// wins; the op is dropped, never silently.
  final void Function(String message)? onError;

  final Map<String, OpHandler> _handlers = {};
  final List<OutboxOp> _queue = [];
  final Map<String, String> _idMap = {};
  bool _online = false;
  bool _replaying = false;
  bool _forceOffline = false;
  bool _initialized = false;

  SyncEngine({
    required this.api,
    required this.store,
    this.onChanged,
    this.onAck,
    this.onError,
  });

  bool get online => _online;
  int get pending => _queue.length;
  List<OutboxOp> get queuedOps => List.unmodifiable(_queue);
  Map<String, String> get idMap => _idMap;

  void register(String type, OpHandler handler) => _handlers[type] = handler;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _queue.addAll(await store.load());
    final saved = await store.loadSession();
    if (saved != null) {
      api.session = AuthSession(
        accessToken: saved.$1,
        refreshToken: saved.$2,
      );
    }
    _emit();
  }

  Future<bool> probe() async {
    if (_forceOffline) {
      _setOnline(false);
      return false;
    }
    final ok = await api.health();
    _setOnline(ok);
    if (ok && _queue.isNotEmpty) {
      await replay();
    }
    return ok;
  }

  void setForceOffline(bool value) {
    _forceOffline = value;
    if (value) _setOnline(false);
  }

  /// Fire-and-forget write path: apply locally first, then push. Pushes that
  /// cannot reach the server are persisted for FIFO replay.
  Future<void> push(String type, Map<String, dynamic> payload) async {
    if (!_online) {
      _enqueue(type, payload);
      return;
    }
    try {
      final data = await _execute(type, payload, newOpId());
      _captureIdMap(payload, data);
      onAck?.call(type, payload, data);
    } on NetworkException {
      _setOnline(false);
      _enqueue(type, payload);
      await probe();
    } on ApiException catch (e) {
      onError?.call(e.message);
    }
  }

  Future<void> replay() async {
    if (_replaying || !_online || _queue.isEmpty) return;
    _replaying = true;
    try {
      while (_queue.isNotEmpty) {
        final op = _queue.first;
        try {
          final data = await _execute(op.type, op.payload, op.id);
          _captureIdMap(op.payload, data);
          _queue.removeAt(0);
          await store.save(_queue);
          _emit();
          onAck?.call(op.type, op.payload, data);
        } on NetworkException {
          _setOnline(false);
          break;
        } on ApiException catch (e) {
          _queue.removeAt(0);
          await store.save(_queue);
          _emit();
          onError?.call(e.message);
        }
      }
    } finally {
      _replaying = false;
    }
  }

  /// Records local→server id mappings (client_id echo) so later queued ops
  /// referencing local ids are rewritten to server ids before executing.
  void _captureIdMap(Map<String, dynamic> payload, Map<String, dynamic>? data) {
    final local = payload['local_id'];
    final server = data?['id'];
    if (local is String && local.isNotEmpty && server is String && server.isNotEmpty) {
      _idMap[local] = server;
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

  void _enqueue(String type, Map<String, dynamic> payload) {
    _queue.add(OutboxOp(id: newOpId(), type: type, payload: payload));
    store.save(_queue);
    _emit();
  }

  void _setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    _emit();
  }

  void _emit() => onChanged?.call(_online, _queue.length);
}

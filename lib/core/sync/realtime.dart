import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';

/// Live events pushed by the backend over Server-Sent Events
/// (`GET /api/v1/ws`). Used for the kitchen board and multi-terminal sync.
class RealtimeChannel {
  final ApiClient api;
  final void Function(String type, Map<String, dynamic> payload) onEvent;
  final void Function(bool connected)? onConnectionChanged;

  http.Client? _client;
  StreamSubscription<List<int>>? _sub;
  Timer? _retry;
  bool _closed = false;
  bool _connected = false;
  String? _lastEventId;

  RealtimeChannel({required this.api, required this.onEvent, this.onConnectionChanged});

  bool get connected => _connected;

  Future<void> connect(String outletId) async {
    if (_closed) return;
    await disconnect();
    final token = api.session?.accessToken ?? '';
    if (token.isEmpty) {
      _scheduleRetry(outletId);
      return;
    }
    // Preferred: exchange the JWT for a single-use connect ticket, so no
    // reusable credential appears in the URL (and in proxy access logs).
    String? ticket;
    try {
      final resp = await api.request('POST', '/api/v1/ws/ticket');
      if (resp is Map && resp['ticket'] is String) ticket = resp['ticket'] as String;
    } catch (_) {
      // Offline / dead session — retry on the normal cadence.
      _scheduleRetry(outletId);
      return;
    }
    final query = <String, String>{
      'outlet_id': outletId,
      if (ticket != null && ticket.isNotEmpty) 'ticket': ticket,
      // Ask the server to replay events newer than our last one on reconnect
      // (backend support: single-instance ring buffer).
      if (_lastEventId != null && _lastEventId!.isNotEmpty) 'last_event_id': _lastEventId!,
    };
    final uri = Uri.parse('${api.baseUrl}/api/v1/ws').replace(queryParameters: query);
    final client = http.Client();
    _client = client;
    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      final response = await client.send(request).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        _scheduleRetry(outletId);
        return;
      }
      _setConnected(true);
      final buffer = StringBuffer();
      _sub = response.stream.listen(
        (chunk) {
          buffer.write(utf8.decode(chunk, allowMalformed: true));
          String block;
          while (true) {
            final idx = buffer.toString().indexOf('\n\n');
            if (idx < 0) break;
            block = buffer.toString().substring(0, idx);
            final rest = buffer.toString().substring(idx + 2);
            buffer
              ..clear()
              ..write(rest);
            _handleBlock(block);
          }
        },
        onDone: () {
          _setConnected(false);
          _scheduleRetry(outletId);
        },
        onError: (_) {
          _setConnected(false);
          _scheduleRetry(outletId);
        },
        cancelOnError: true,
      );
    } catch (_) {
      _setConnected(false);
      _scheduleRetry(outletId);
    }
  }

  void _handleBlock(String block) {
    String? data;
    String? eventId;
    for (final line in block.split('\n')) {
      if (line.startsWith('id:')) {
        eventId = line.substring(3).trim();
      } else if (line.startsWith('data:')) {
        data = (data ?? '') + line.substring(5).trim();
      }
    }
    if (eventId != null && eventId.isNotEmpty) {
      _lastEventId = eventId;
    }
    if (data == null || data.isEmpty) return;
    try {
      final evt = jsonDecode(data);
      if (evt is Map && evt['type'] is String && evt['payload'] is Map) {
        onEvent(
          evt['type'] as String,
          (evt['payload'] as Map).cast<String, dynamic>(),
        );
      }
    } catch (_) {}
  }

  void _scheduleRetry(String outletId) {
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 6), () => connect(outletId));
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onConnectionChanged?.call(value);
  }

  Future<void> disconnect() async {
    _retry?.cancel();
    await _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
    _setConnected(false);
  }

  Future<void> dispose() async {
    _closed = true;
    await disconnect();
  }
}

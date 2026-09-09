import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_media_types;

/// Server rejected a request with a structured error envelope.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// The server could not be reached at all (offline, timeout, DNS, ...).
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);

  @override
  String toString() => message;
}

class AuthSession {
  String accessToken;
  String refreshToken;
  AuthSession({required this.accessToken, required this.refreshToken});
}

class ApiClient {
  final String baseUrl;
  final http.Client _http;
  final void Function(AuthSession?)? onSessionChanged;
  AuthSession? session;

  ApiClient({
    required String baseUrl,
    http.Client? client,
    this.onSessionChanged,
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _http = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) {
    final cleaned = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$baseUrl/$cleaned').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Map<String, String> _headers() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final token = session?.accessToken;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
    Map<String, String>? query,
    bool auth = true,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    return _send(method, path, body, idempotencyKey, query, auth, timeout);
  }

  Future<dynamic> _send(
    String method,
    String path,
    Object? body,
    String? idempotencyKey,
    Map<String, String>? query,
    bool auth,
    Duration timeout, {
    bool retried = false,
  }) async {
    final uri = _uri(path, query);
    final headers = _headers();
    if (!auth) headers.remove('Authorization');
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;

    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed =
          await _http.send(req).timeout(timeout, onTimeout: () => throw TimeoutException('request timeout'));
      res = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw NetworkException('Request timed out: $path');
    } catch (e) {
      throw NetworkException('Network unreachable: $path');
    }

    if (res.statusCode == 401 && auth && session != null && !retried) {
      final refreshed = await refreshSession();
      if (refreshed) {
        return _send(method, path, body, idempotencyKey, query, auth, timeout, retried: true);
      }
    }

    if (res.statusCode >= 300) {
      throw _errorFrom(res);
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  ApiException _errorFrom(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map && decoded['error'] is Map) {
        final err = decoded['error'] as Map;
        return ApiException(
          res.statusCode,
          (err['code'] ?? 'error').toString(),
          (err['message'] ?? res.reasonPhrase ?? 'Request failed').toString(),
        );
      }
    } catch (_) {}
    return ApiException(res.statusCode, 'http_${res.statusCode}', res.reasonPhrase ?? 'Request failed');
  }

  Future<bool> health() async {
    try {
      final res = await _http.get(_uri('/healthz')).timeout(const Duration(milliseconds: 1500));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Logs in and stores the session. Returns the token response (including
  /// the `staff` object) so callers can cache server-verified identities.
  Future<Map<String, dynamic>> login(String staffId, String pin, String outletId) async {
    final data = await request('POST', '/api/v1/auth/login', body: {
      'staff_id': staffId,
      'pin': pin,
      'outlet_id': outletId,
    }, auth: false);
    _storeSession(data);
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<bool> refreshSession() async {
    final refresh = session?.refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final data = await request('POST', '/api/v1/auth/refresh',
          body: {'refresh_token': refresh}, auth: false);
      _storeSession(data);
      return true;
    } catch (_) {
      session = null;
      onSessionChanged?.call(null);
      return false;
    }
  }

  void _storeSession(dynamic data) {
    if (data is! Map) return;
    final token = data['token'];
    final refresh = data['refresh_token'];
    if (token is! String || token.isEmpty) return;
    session = AuthSession(
      accessToken: token,
      refreshToken: refresh is String ? refresh : '',
    );
    onSessionChanged?.call(session);
  }

  Future<void> logout() async {
    final refresh = session?.refreshToken;
    session = null;
    onSessionChanged?.call(null);
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await request('POST', '/api/v1/auth/logout', body: {'refresh_token': refresh}, auth: false);
      } catch (_) {}
    }
  }

  /// FR-A3: authorize a privileged action against the server's manager/admin
  /// PINs (bcrypt-hashed server-side). Returns the matching staff (so callers
  /// can cache the identity offline) or null when the PIN doesn't verify.
  /// Throws NetworkException when offline — callers fall back to the
  /// locally cached PinVault then.
  Future<Map<String, dynamic>?> verifyManagerPin(String pin) async {
    final data = await request('POST', '/api/v1/auth/verify-manager-pin', body: {'pin': pin});
    if (data is Map && data['valid'] == true && data['staff'] is Map) {
      return (data['staff'] as Map).cast<String, dynamic>();
    }
    return null;
  }

  /// Uploads an image (menu photo) as multipart/form-data. Returns the JSON
  /// response body (the server answers with `{"image_url": "/media/…"}`).
  Future<Map<String, dynamic>> uploadImage({
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String>? query,
    String path = '/api/v1/uploads/menu-image',
    bool retried = false,
  }) async {
    final uri = _uri(path, query);
    final req = http.MultipartRequest('POST', uri);
    final token = session?.accessToken;
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: http_media_types.MediaType.parse(contentType),
    ));

    http.Response res;
    try {
      final streamed =
          await _http.send(req).timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('upload timeout');
      });
      res = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw NetworkException('Upload timed out');
    } catch (e) {
      throw NetworkException('Network unreachable: upload failed');
    }

    if (res.statusCode == 401 && session != null && !retried) {
      if (await refreshSession()) {
        return uploadImage(bytes: bytes, filename: filename, contentType: contentType, query: query, path: path, retried: true);
      }
    }
    if (res.statusCode >= 300) {
      throw _errorFrom(res);
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  void dispose() => _http.close();
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// First-party analytics for the Nexory admin panel (nexorytechnologies.com/admin/apps).
///
/// Sends sessions, screen views, custom events and crashes to
/// `POST /api/apps/events` with the app's `X-App-Key`. Events are batched and
/// flushed every 30 s, when a batch fills, and when the app goes to background.
/// The user id is a random per-install id — never a phone number or email.
/// Analytics must never break the app: every failure is swallowed.
class AppAnalytics with WidgetsBindingObserver {
  AppAnalytics._();
  static final AppAnalytics instance = AppAnalytics._();

  static const _endpoint = 'https://nexorytechnologies.com/api/apps/events/';
  static const _maxBatch = 50;

  String _key = '';
  String _version = '';
  String _userId = '';
  String _sessionId = '';
  final List<Map<String, Object?>> _queue = [];
  Timer? _timer;
  bool _started = false;
  DateTime? _pausedAt;

  /// Call once from `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
  /// [appVersion] should match pubspec `version` (e.g. "1.0.5+6").
  Future<void> init({required String appKey, required String appVersion}) async {
    if (_started || appKey.isEmpty || kIsWeb) return;
    _started = true;
    _key = appKey;
    _version = appVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getString('nx_analytics_uid') ?? _randomId();
      await prefs.setString('nx_analytics_uid', _userId);
    } catch (_) {
      _userId = _randomId();
    }
    _hookErrors();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
    _startSession();
  }

  /// Custom event, e.g. `AppAnalytics.instance.event('order_created', {'items': 3})`.
  void event(String name, [Map<String, Object?>? props]) => _add('event', name, props);

  /// Screen view; also recorded automatically by [observer] for named routes.
  void screen(String name) => _add('screen', name);

  /// Attach to `MaterialApp.navigatorObservers` to log screen views.
  late final NavigatorObserver observer = _ScreenObserver(this);

  void _startSession() {
    _sessionId = _randomId();
    _add('session_start', null);
  }

  void _hookErrors() {
    final prevFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      _add('crash', details.exceptionAsString(), {
        'stack': details.stack?.toString().split('\n').take(8).join('\n'),
        'library': details.library,
      });
      flush();
      prevFlutter?.call(details);
    };
    final prevPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _add('crash', error.toString(), {'stack': stack.toString().split('\n').take(8).join('\n')});
      flush();
      return prevPlatform?.call(error, stack) ?? false;
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      flush();
    } else if (state == AppLifecycleState.resumed) {
      // Back after 30 min in the background counts as a new session.
      final p = _pausedAt;
      if (p != null && DateTime.now().difference(p) > const Duration(minutes: 30)) _startSession();
      _pausedAt = null;
    }
  }

  void _add(String type, String? name, [Map<String, Object?>? props]) {
    if (!_started) return;
    final osVersion = Platform.operatingSystemVersion;
    _queue.add({
      'type': type,
      if (name != null) 'name': name.length > 80 ? name.substring(0, 80) : name,
      'session_id': _sessionId,
      'user_id': _userId,
      'app_version': _version,
      'os_version': '${Platform.operatingSystem} ${osVersion.length > 12 ? osVersion.substring(0, 12) : osVersion}',
      'device': Platform.operatingSystem,
      'at': DateTime.now().toUtc().toIso8601String(),
      'props': ?props,
    });
    if (_queue.length >= _maxBatch) flush();
  }

  bool _flushing = false;

  /// Sends queued events; failed batches are kept (up to 500) for the next try.
  Future<void> flush() async {
    if (_flushing || _queue.isEmpty || _key.isEmpty) return;
    _flushing = true;
    final batch = List<Map<String, Object?>>.of(_queue.take(100));
    try {
      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json', 'X-App-Key': _key},
            body: jsonEncode({'events': batch}),
          )
          .timeout(const Duration(seconds: 10));
      // Drop on success, and on 4xx (bad key/payload would never succeed on retry).
      if (res.statusCode < 500 && res.statusCode != 429) _queue.removeRange(0, batch.length);
    } catch (_) {
      // Offline: keep for later, but don't grow without bound.
      if (_queue.length > 500) _queue.removeRange(0, _queue.length - 500);
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  static String _randomId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

class _ScreenObserver extends NavigatorObserver {
  _ScreenObserver(this._a);
  final AppAnalytics _a;

  void _log(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (route is PageRoute && name != null && name.isNotEmpty) _a.screen(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _log(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _log(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _log(previousRoute);
}

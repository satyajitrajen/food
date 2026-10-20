import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api/api_client.dart';
import '../core/api/dto.dart';
import '../core/auth/session_store.dart';
import '../core/auth/tenant.dart';
import '../core/notifications/push_notification_service.dart';
import '../core/printing/printing.dart';
import '../core/printing/receipt_builder.dart';
import '../core/sync/op_specs.dart';
import '../core/sync/outbox.dart';
import '../core/sync/realtime.dart';
import '../core/sync/sync_engine.dart';
import '../models/app_nav.dart';
import '../models/staff_model.dart';
import '../models/outlet_model.dart';
import '../models/report_model.dart';
import '../models/shift_model.dart';
import '../models/table_model.dart';
import '../models/menu_model.dart';
import '../models/order_model.dart';
import '../models/kot_model.dart';
import '../models/expense_model.dart';
import '../models/cash_model.dart';
import '../models/customer_model.dart';
import '../models/inventory_model.dart';
import '../models/settings_model.dart';
import '../models/subscription_model.dart';

/// API base URL; override with --dart-define=FOODPOS_API_URL=...
const String kDefaultApiBaseUrl =
    String.fromEnvironment('FOODPOS_API_URL', defaultValue: 'https://food.nexorytechnologies.com');

class PosProvider extends ChangeNotifier {
  /// When true the provider talks to the Go backend: every write is sent to
  /// the server and awaited (no on-device queue), reads come from the server,
  /// SSE keeps terminals in sync. False = demo/test mode.
  final bool apiEnabled;
  ApiClient? _api;
  SyncEngine? _sync;
  RealtimeChannel? _realtime;
  PrinterAdapter? _printer;
  TenantStore? _tenantStore;
  SessionStore? _sessionStore;
  TenantInfo? _tenant;
  EntitlementSnapshot? _entitlement;
  bool _hydrating = false;
  String? _lastSyncError;
  DateTime? _lastSyncAt;
  String? _printerError;

  /// Completes once boot hydration + saved-login restore finish. Screens
  /// (e.g. Splash) await this instead of guessing with a fixed delay.
  Future<void>? _readyFuture;
  Future<void> get ready => _readyFuture ?? Future.value();
  bool _bootstrapped = false;
  bool get bootstrapDone => _bootstrapped;

  String? get lastSyncError => _lastSyncError;
  DateTime? get lastSyncAt => _sync?.lastSyncAt ?? _lastSyncAt;

  /// Writes that were not saved, newest first — shown in the connection
  /// panel so a refused payment or refund is never invisible.
  final List<SyncRejection> _rejections = [];
  List<SyncRejection> get syncRejections => List.unmodifiable(_rejections);
  void clearSyncRejections() {
    _rejections.clear();
    _lastSyncError = null;
    notifyListeners();
  }
  String? get printerError => _printerError;

  /// One message per write that was not saved; the app shell shows each as
  /// a snackbar.
  final StreamController<String> _saveErrors = StreamController<String>.broadcast();
  Stream<String> get saveErrors => _saveErrors.stream;

  /// Why the last login failed when it was not a wrong PIN (no internet,
  /// server error). Null after a wrong PIN or a successful login.
  String? _loginError;
  String? get loginError => _loginError;

  PosProvider({this.apiEnabled = false, PrinterAdapter? printer, @visibleForTesting ApiClient? api}) {
    _printer = printer;
    // No secrets: only the staff/outlet snapshot (tokens stay in OutboxStore,
    // PINs only as salted vault hashes), so this is kept in every mode.
    _sessionStore = SessionStore();
    if (apiEnabled) {
      _api = api ?? ApiClient(baseUrl: kDefaultApiBaseUrl, onSessionChanged: _persistSession);
      _tenantStore = TenantStore();
      _sync = SyncEngine(
        api: _api!,
        store: OutboxStore(),
        onChanged: (_, _) => notifyListeners(),
        onAck: applyServerTruth,
        onRejected: _onOpRejected,
        onReconnect: _onReconnect,
      );
      _registerOps();
      _sync!.startProbing();
      _readyFuture = _bootstrap();
    }
  }

  bool _disposed = false;

  /// Background re-reads can finish after the provider is gone.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _dashboardRefresh?.cancel();
    _sync?.dispose();
    unawaited(_saveErrors.close());
    unawaited(_realtime?.disconnect());
    super.dispose();
  }

  void _persistSession(AuthSession? session) {
    unawaited(OutboxStore().saveSession(session?.accessToken, session?.refreshToken));
  }

  /// Runs a boot phase with a hard cap so startup can never hang forever on
  /// a stalled read (storage or network). A timed-out phase behaves as if it
  /// returned nothing — boot continues offline toward PIN login.
  Future<T?> _bootPhase<T>(Future<T> phase, {int seconds = 5}) async {
    try {
      return await phase.timeout(Duration(seconds: seconds));
    } catch (_) {
      return null;
    }
  }

  Future<void> _bootstrap() async {
    // Older builds cached PIN hashes for offline sign-in; sign-in is
    // server-only now, so drop them.
    unawaited(SharedPreferences.getInstance()
        .then((p) => p.remove('foodpos.pinvault'))
        .then((_) {}, onError: (_) {}));
    // Restore the bound tenant + last entitlement before any network calls so
    // hydrations are org-scoped and offline grace survives restarts.
    if (_tenantStore != null) {
      _tenant = await _bootPhase<TenantInfo?>(_tenantStore!.load());
      _entitlement =
          await _bootPhase<EntitlementSnapshot?>(_tenantStore!.loadEntitlement());
    }
    try {
      await _sync!.initialize().timeout(const Duration(seconds: 5));
      await _sync!.probe().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Boot continues offline; the PIN screen stays available.
    }
    if ((_sync?.online ?? false) && _tenant != null) {
      await _bootPhase(hydratePublic(), seconds: 10);
    }
    // Stay signed in across restarts: whoever was logged in keeps working
    // until an explicit logout. Only then is the PIN screen shown.
    await _bootPhase(restoreSavedLogin(), seconds: 15);
    _bootstrapped = true;
    notifyListeners();
    PushNotificationService.instance.onTokenRefresh.listen((token) {
      if (_currentStaff != null && _api != null) {
        unawaited(_api!.registerDeviceToken(token));
      }
    });
    // Push payloads are short string summaries, not full records, so they
    // only prompt a re-read; the live SSE stream already covers connected
    // terminals.
    PushNotificationService.instance.onMessage.listen((msg) {
      if (msg.data['type'] == null || realtimeConnected || _currentStaff == null) return;
      unawaited(triggerSync());
    });
  }

  /// Public retry for the menu/catalog hydrate. Covers the real case where
  /// the login-time [hydrateOutlet] fails (transient network) and never
  /// retries — UI can call this on pull-to-refresh or after a failed login
  /// hydrate. Idempotent and safe to call repeatedly.
  Future<void> refreshMenu() async {
    if (!apiEnabled || _api == null) return;
    await _sync?.probe();
    if (!(_sync?.online ?? false)) {
      _lastSyncError = 'Server unreachable — using cached data';
      notifyListeners();
      return;
    }
    _hydrating = false;
    await hydrateOutlet();
    if (_menuItems.isEmpty && (_sync?.online ?? false)) {
      await Future.delayed(const Duration(seconds: 1));
      _hydrating = false;
      await hydrateOutlet();
    }
  }

  Future<void> _postLoginSync() async {
    if (!apiEnabled) return;
    await refreshMenu();
    if (_sync!.online) {
      final token = PushNotificationService.instance.fcmToken;
      if (token != null && token.isNotEmpty && _api != null) {
        unawaited(_api!.registerDeviceToken(token));
      }
    }
    _connectRealtime();
  }

  void _connectRealtime() {
    if (!apiEnabled || _api == null) return;
    _realtime ??= RealtimeChannel(
      api: _api!,
      onEvent: _applyRealtimeEvent,
      onConnectionChanged: (_) => notifyListeners(),
    );
    unawaited(_realtime!.connect(_currentOutlet.id));
  }

  void _applyRealtimeEvent(String type, Map<String, dynamic> payload) {
    // Strict outlet isolation: ignore realtime events for other outlets
    // (a mis-scoped SSE subscription must never pollute this terminal).
    final eventOutlet = payload['outlet_id']?.toString() ?? '';
    if (eventOutlet.isNotEmpty && eventOutlet != _currentOutlet.id) return;
    switch (type) {
      case 'order.updated':
        _upsertServerOrder(payload);
        break;
      case 'kot.created':
      case 'kot.updated':
        _upsertServerKot(payload);
        break;
      case 'table.updated':
        _upsertServerTable(payload);
        break;
      case 'table.deleted':
        _tables.removeWhere((t) => t.id == payload['id']?.toString());
        break;
      case 'shift.updated':
        _applyServerShift(payload);
        break;
      case 'settings.updated':
        _settings = _withOutletProfile(settingsFromApi(payload));
        break;
      case 'outlet.updated':
        if (payload['id'] == _currentOutlet.id) {
          _currentOutlet = outletFromApi(payload);
          _settings = _withOutletProfile(_settings);
        }
        break;
      // Another terminal changed a back-office record: re-read that list.
      case 'menu.changed':
        unawaited(_refresh(['menu']));
        break;
      case 'staff.changed':
        unawaited(_refresh(['staff']));
        break;
      case 'customer.changed':
        unawaited(_refresh(['customers']));
        break;
      case 'expense.changed':
        unawaited(_refresh(['expenses', 'shift']));
        break;
      case 'inventory.changed':
        unawaited(_refresh(['inventory']));
        break;
      case 'supplier.changed':
        unawaited(_refresh(['suppliers']));
        break;
      case 'purchase.changed':
        unawaited(_refresh(['purchases', 'inventory', 'suppliers']));
        break;
      default:
        break;
    }
    if (type == 'order.updated' || type == 'shift.updated') _scheduleDashboardRefresh();
    notifyListeners();
  }

  Timer? _dashboardRefresh;

  /// Re-reads the admin dashboard a moment after sales activity (debounced,
  /// so a burst of item adds costs one request), keeping KPIs current.
  void _scheduleDashboardRefresh() {
    if (!apiEnabled || _currentStaff?.role != StaffRole.admin) return;
    _dashboardRefresh?.cancel();
    _dashboardRefresh = Timer(const Duration(seconds: 3), () async {
      final dash = await _tryRead('/api/v1/reports/dashboard', {'outlet_id': _currentOutlet.id});
      if (dash is Map) {
        _serverDashboard = dashboardReportFromApi(dash.cast<String, dynamic>());
        notifyListeners();
      }
    });
  }

  MenuItem? _menuLookup(String id) =>
      _menuItems.where((m) => m.id == id).firstOrNull;

  /// Re-binds this terminal to a different org (change-code flow): clears the
  /// previous tenant + entitlement + signed-in staff, then bootstraps the
  /// new code.
  Future<void> rebindOrg(String code) async {
    _tenant = null;
    _entitlement = null;
    _currentStaff = null;
    _staffList.clear();
    _outlets.clear();
    await _tenantStore?.clear();
    await _tenantStore?.clearEntitlement();
    await _sessionStore?.clear();
    notifyListeners();
    await bootstrapOrg(code);
  }

  // ---- Server-truth upserts (API acks + SSE events) ----

  void _upsertServerOrder(Map<String, dynamic> j, {String? replaceLocalId}) {
    final serverId = j['id']?.toString() ?? '';
    if (serverId.isEmpty) return;
    final clientId = j['client_id']?.toString();
    final incoming = orderFromApi(j, _menuLookup);
    String? oldId;
    var idx = -1;    for (var i = 0; i < _orders.length; i++) {
      final o = _orders[i];
      if (o.id == serverId ||
          (clientId != null && clientId.isNotEmpty && o.id == clientId) ||
          (replaceLocalId != null && o.id == replaceLocalId)) {
        idx = i;
        oldId = o.id;
        break;
      }
    }
    if (idx >= 0) {
      _orders[idx] = incoming;
    } else {
      _orders.insert(0, incoming);
    }
    if (_activeOrder != null &&
        (_activeOrder!.id == serverId ||
            _activeOrder!.id == oldId ||
            (clientId != null && clientId.isNotEmpty && _activeOrder!.id == clientId) ||
            (replaceLocalId != null && _activeOrder!.id == replaceLocalId))) {
      _activeOrder = incoming;
    }
    final table = incoming.tableId == null
        ? null
        : _tables.where((t) => t.id == incoming.tableId).firstOrNull;
    if (table != null) {
      if (incoming.isClosed) {
        table
          ..status = TableStatus.available
          ..activeOrderId = null
          ..currentOrderAmount = 0.0;
      } else {
        table
          ..status = TableStatus.occupied
          ..activeOrderId = incoming.id
          ..currentOrderAmount = incoming.grandTotal;
      }
    }
  }

  void _upsertServerKot(Map<String, dynamic> j) {
    final incoming = kotFromApi(j);
    // Strict outlet isolation: never persist another outlet's ticket, even if
    // a realtime event or ack leaks across outlets.
    if (incoming.outletId.isNotEmpty && incoming.outletId != _currentOutlet.id) {
      return;
    }
    final idx = _kots.indexWhere((k) => k.id == incoming.id);
    var prevStatus = idx >= 0 ? _kots[idx].status : null;
    if (idx >= 0) {
      _kots[idx] = incoming;
    } else if (_adoptPendingServerKot(incoming)) {
      // Local optimistic copy absorbed; the server ticket took its place.
      prevStatus = null;
    } else {
      _kots.insert(0, incoming);
    }
    _maybeFireReadyAlert(previous: prevStatus, kot: incoming);
  }

  /// Replaces the terminal's optimistic [KOT] for an order with the server's
  /// authoritative copy. Without this, every fire rendered twice on the KDS:
  /// once as the local guess (terminal counter) and once as the server ticket
  /// (outlet counter) that arrives right after via ack/SSE. Matching is by
  /// order + exact item multiset so legitimate multi-fire tickets (different
  /// courses fired separately) never collapse into each other.
  bool _adoptPendingServerKot(KitchenOrderTicket incoming) {
    if (incoming.items.isEmpty) return false;
    final pending = _kots.indexWhere((k) =>
        k.pendingServerAck &&
        k.orderId == incoming.orderId &&
        _sameTicketItems(k, incoming));
    if (pending == -1) return false;
    final local = _kots[pending];
    local
      ..id = incoming.id
      ..kotNumber = incoming.kotNumber
      ..status = incoming.status
      ..pendingServerAck = false
      ..items
          .clear()
      ..items.addAll(incoming.items);
    return true;
  }

  bool _sameTicketItems(KitchenOrderTicket a, KitchenOrderTicket b) {
    String sig(KitchenOrderTicket k) {
      final names = k.items
          .where((i) => !i.isCancelled)
          .map((i) => '${i.menuItem.name} x${i.quantity}')
          .toList()
        ..sort();
      return names.join('|');
    }

    return sig(a) == sig(b) && sig(a).isNotEmpty;
  }

  void _upsertServerTable(Map<String, dynamic> j, {String? replaceLocalId}) {
    final incoming = tableFromApi(j);
    if (replaceLocalId != null) _tables.removeWhere((t) => t.id == replaceLocalId);
    if (incoming.assignedWaiter != null) {
      final waiter = _staffList.where((s) => s.id == incoming.assignedWaiter).firstOrNull;
      if (waiter != null) {
        incoming.assignedWaiter = waiter.name;
      }
    }
    final idx = _tables.indexWhere((t) => t.id == incoming.id);
    if (idx >= 0) {
      _tables[idx] = incoming;
    } else {
      _tables.add(incoming);
    }
  }

  void _applyServerShift(Map<String, dynamic> j) {
    final incoming = shiftFromApi(j);
    if (incoming.isClosed) {
      if (_currentShift?.id == incoming.id) {
        _currentShift = null;
      }
      final idx = _shiftHistory.indexWhere((s) => s.id == incoming.id);
      if (idx >= 0) {
        _shiftHistory[idx] = incoming;
      } else {
        _shiftHistory.insert(0, incoming);
      }
    } else {
      _currentShift = incoming;
    }
  }

  void _upsertServerExpense(Map<String, dynamic> j, {String? replaceLocalId}) {
    final incoming = expenseFromApi(j);
    final idx = _expenses.indexWhere((e) =>
        e.id == incoming.id || (replaceLocalId != null && e.id == replaceLocalId));
    if (idx >= 0) {
      _expenses[idx] = incoming;
    } else {
      _expenses.insert(0, incoming);
    }
  }

  void _upsertServerCustomer(Map<String, dynamic> j, {String? replaceLocalId}) {
    final incoming = customerFromApi(j);
    final idx = _customers.indexWhere((c) =>
        c.id == incoming.id ||
        (replaceLocalId != null && c.id == replaceLocalId) ||
        c.phone == incoming.phone);
    if (idx >= 0) {
      _customers[idx] = incoming;
    } else {
      _customers.insert(0, incoming);
    }
  }

  void _upsertServerInventoryItem(Map<String, dynamic> j, {String? replaceLocalId}) {
    final incoming = inventoryItemFromApi(j);
    if (replaceLocalId != null) _inventory.removeWhere((i) => i.id == replaceLocalId);
    final idx = _inventory.indexWhere((i) => i.id == incoming.id);
    if (idx >= 0) {
      _inventory[idx] = incoming;
    } else {
      _inventory.add(incoming);
    }
  }

  void _upsertServerMenuItem(Map<String, dynamic> j, {String? replaceLocalId}) {
    final incoming = menuItemFromApi(j);
    final idx = _menuItems.indexWhere((m) =>
        m.id == incoming.id ||
        (replaceLocalId != null && m.id == replaceLocalId));
    if (idx >= 0) {
      _menuItems[idx] = incoming;
    } else {
      _menuItems.add(incoming);
    }
    _rebuildCategories();
  }

  void _removeLocalMenuItem(String? id) {
    if (id == null || id.isEmpty) return;
    _menuItems.removeWhere((m) => m.id == id || m.id == (_sync?.idMap[id] ?? ''));
    _rebuildCategories();
  }

  void _upsertServerStaff(Map<String, dynamic> j, {String? replaceLocalId}) {
    final incoming = staffFromApi(j);
    final idx = _staffList.indexWhere((s) =>
        s.id == incoming.id ||
        (replaceLocalId != null && s.id == replaceLocalId));
    if (idx >= 0) {
      _staffList[idx] = incoming;
    } else {
      _staffList.add(incoming);
    }
  }

  void _upsertServerSupplier(Map<String, dynamic> j, {String? replaceLocalId}) {
    final incoming = supplierFromApi(j);
    final idx = _suppliers.indexWhere((s) =>
        s.id == incoming.id ||
        (replaceLocalId != null && s.id == replaceLocalId));
    if (idx >= 0) {
      _suppliers[idx] = incoming;
    } else {
      _suppliers.add(incoming);
    }
  }

  void _upsertServerPurchase(Map<String, dynamic> j, {String? replaceLocalId}) {
    final incoming = purchaseFromApi(j);
    final idx = _purchases.indexWhere((p) =>
        p.id == incoming.id ||
        (replaceLocalId != null && p.id == replaceLocalId));
    if (idx >= 0) {
      _purchases[idx] = incoming;
    } else {
      _purchases.insert(0, incoming);
    }
  }

  /// Called by the SyncEngine when the server confirms any queued write
  /// (direct or replayed). Server truth replaces optimistic local state.
  void applyServerTruth(
      String type, Map<String, dynamic> payload, Map<String, dynamic>? data) {
    _lastSyncAt = DateTime.now();
    switch (type) {
      case 'order.create':
      case 'order.patch':
      case 'order.add_item':
      case 'item.qty':
      case 'item.cancel':
      case 'order.pay':
      case 'order.refund':
        if (data != null) {
          _upsertServerOrder(data, replaceLocalId: payload['local_id']?.toString());
        }
        break;
      case 'kot.fire':
      case 'kot.status':
        if (data != null) _upsertServerKot(data);
        break;
      case 'shift.open':
      case 'shift.close':
        if (data != null) _applyServerShift(data);
        break;
      case 'expense.create':
        if (data != null) {
          _upsertServerExpense(data, replaceLocalId: payload['local_id']?.toString());
        }
        unawaited(_refresh(['shift']));
        break;
      case 'customer.create':
        if (data != null) {
          _upsertServerCustomer(data, replaceLocalId: payload['local_id']?.toString());
        }
        break;
      case 'credit.book':
        if (data != null) _upsertServerCustomer(data);
        break;
      case 'stock.adjust':
        if (data != null) _upsertServerInventoryItem(data);
        break;
      case 'menu.create':
      case 'menu.update':
        if (data != null) _upsertServerMenuItem(data, replaceLocalId: payload['local_id']?.toString());
        break;
      case 'menu.delete':
        _removeLocalMenuItem(payload['menu_item_id']?.toString());
        break;
      case 'staff.create':
      case 'staff.patch':
        if (data != null) _upsertServerStaff(data, replaceLocalId: payload['local_id']?.toString());
        break;
      case 'inventory.create':
        if (data != null) {
          _upsertServerInventoryItem(data, replaceLocalId: payload['local_id']?.toString());
        }
        break;
      case 'inventory.patch':
        if (data != null) _upsertServerInventoryItem(data);
        break;
      case 'inventory.delete':
        _inventory.removeWhere((i) => i.id == payload['inventory_item_id']);
        break;
      case 'customer.patch':
        if (data != null) _upsertServerCustomer(data);
        break;
      case 'customer.delete':
        _customers.removeWhere((c) => c.id == payload['customer_id']);
        break;
      case 'supplier.patch':
        if (data != null) _upsertServerSupplier(data);
        break;
      case 'supplier.delete':
        _suppliers.removeWhere((x) => x.id == payload['supplier_id']);
        break;
      case 'expense.patch':
        if (data != null) _upsertServerExpense(data);
        unawaited(_refresh(['shift']));
        break;
      case 'order.cancel':
        if (data != null) _upsertServerOrder(data);
        unawaited(_refresh(['tables', 'kots']));
        break;
      case 'settings.update':
        if (data != null) {
          _settings = _withOutletProfile(settingsFromApi(data));
        }
        // Open bills were re-rated by the server.
        unawaited(_refresh(['orders', 'tables']));
        break;
      case 'outlet.patch':
        if (data != null && data['id'] == _currentOutlet.id) {
          _currentOutlet = outletFromApi(data);
          final i = _outlets.indexWhere((o) => o.id == _currentOutlet.id);
          if (i >= 0) _outlets[i] = _currentOutlet;
          _settings = _withOutletProfile(_settings);
        }
        break;
      case 'expense.delete':
      case 'cash.move':
        // The drawer totals are the server's.
        unawaited(_refresh(['shift']));
        if (type == 'cash.move') unawaited(fetchCashMoves());
        break;
      case 'table.status':
      case 'table.move':
      case 'table.merge':
      case 'table.unmerge':
      case 'table.delete':
        unawaited(_refresh(['tables', 'orders']));
        break;
      case 'supplier.create':
        if (data != null) _upsertServerSupplier(data, replaceLocalId: payload['local_id']?.toString());
        break;
      case 'supplier.payment':
        unawaited(_refresh(['shift']));
        if (data != null) {
          final supplier = data['supplier'];
          if (supplier is Map) {
            _upsertServerSupplier(supplier.cast<String, dynamic>());
          }
          final pay = data['payment'];
          if (pay is Map) {
            final incoming = supplierPaymentFromApi(pay.cast<String, dynamic>());
            final localId = payload['local_id']?.toString();
            final idx = _supplierPayments.indexWhere((p) =>
                p.id == incoming.id ||
                (localId != null && p.id == localId));
            if (idx >= 0) {
              _supplierPayments[idx] = incoming;
            } else {
              _supplierPayments.insert(0, incoming);
            }
          }
        }
        break;
      case 'purchase.create':
      case 'purchase.patch':
        if (data != null) _upsertServerPurchase(data, replaceLocalId: payload['local_id']?.toString());
        // Stock and supplier balances are the server's.
        unawaited(_refresh(['inventory', 'suppliers']));
        break;
      case 'table.create':
        if (data != null) _upsertServerTable(data, replaceLocalId: payload['local_id']?.toString());
        break;
      case 'table.patch':
        if (data != null) _upsertServerTable(data);
        break;
      default:
        break;
    }
    notifyListeners();
  }

  // ---- Cache-first reads ----

  /// The public roster is fetched per outlet and carries no outlet ids, so
  /// single-outlet roles (waiter, kitchen) are bound to the outlet it was
  /// fetched for; otherwise they could never pass canAccessOutlet.
  Staff _bindRosterOutlet(Staff s) {
    if (s.outletId != null || _currentOutlet.isNone) return s;
    if (s.role != StaffRole.waiter && s.role != StaffRole.kitchen) return s;
    return Staff(
      id: s.id,
      outletId: _currentOutlet.id,
      name: s.name,
      role: s.role,
      pin: s.pin,
      avatarUrl: s.avatarUrl,
      mobile: s.mobile,
      isActive: s.isActive,
      isProtected: s.isProtected,
    );
  }

  Future<void> hydratePublic() async {
    if (!apiEnabled || _api == null) return;
    try {
      final orgQuery = _tenant == null ? null : {'org_code': _tenant!.orgCode};
      final outlets = await _api!.request('GET', '/api/v1/outlets',
          auth: false, query: orgQuery);
      if (outlets is Map && outlets['outlets'] is List) {
        _outlets
          ..clear()
          ..addAll((outlets['outlets'] as List)
              .whereType<Map>()
              .map((o) => outletFromApi(o.cast<String, dynamic>())));
        if (_currentOutlet.isNone && _outlets.isNotEmpty) _currentOutlet = _outlets.first;
      }
      // The public roster is filtered server-side to staff who can sign in at
      // this outlet (it no longer carries outlet ids).
      final staff = await _api!.request('GET', '/api/v1/staff', auth: false, query: {
        ...?orgQuery,
        if (!_currentOutlet.isNone) 'outlet_id': _currentOutlet.id,
      });
      if (staff is Map && staff['staff'] is List) {
        _staffList
          ..clear()
          ..addAll((staff['staff'] as List)
              .whereType<Map>()
              .map((s) => staffFromApi(s.cast<String, dynamic>()))
              .where((s) => s.isActive)
              .map(_bindRosterOutlet));
      }
      _lastSyncAt = DateTime.now();
      _lastSyncError = null;
      notifyListeners();
    } on NetworkException {
      _lastSyncError = 'Server unreachable — using cached data';
    } on ApiException catch (e) {
      _lastSyncError = e.message;
    }
  }

  // ---- SaaS tenant + license ----

  /// True when this API terminal still needs an org code before login. Only
  /// when the server is reachable: offline first-run keeps the PIN screen
  /// (legacy fallback) instead of trapping staff on an unreachable setup page.
  bool get needsOrgSetup =>
      apiEnabled && _tenant == null && (_sync?.online ?? false);
  String? get orgCode => _tenant?.orgCode;
  String? get tenantOrgName => _tenant?.orgName;
  EntitlementSnapshot? get entitlement => _entitlement;

  /// Paid-writes allowed? Demo mode is always licensed; API terminals need a
  /// trial/active entitlement inside the (grace-extended) window.
  bool get licenseActive => !apiEnabled || (_entitlement?.isActive ?? false);
  bool get canTakeOrders => licenseActive;
  int get licenseDaysLeft => _entitlement?.daysLeft ?? 0;
  bool get licenseTokenVerified => _entitlement?.tokenVerified ?? false;
  bool get isTrial => _entitlement?.status == 'trial';

  /// Trial countdown prefers the subscription card (server truth with
  /// trial_ends_at) and falls back to the cached entitlement window.
  int get trialDaysLeft {
    final fromCard = _subscriptionStatus?.trialDaysLeft ?? 0;
    if (fromCard > 0) return fromCard;
    if (isTrial) return licenseDaysLeft;
    return 0;
  }

  // ---- Subscription card (Settings, admins) ----

  SubscriptionStatus? _subscriptionStatus;
  String? _subscriptionStatusError;
  String? _subscriptionActionError;

  SubscriptionStatus? get subscriptionStatus => _subscriptionStatus;
  String? get subscriptionStatusError => _subscriptionStatusError;
  String? get subscriptionActionError => _subscriptionActionError;

  /// Staff-scoped read for the Settings subscription card. Registered outside
  /// the entitlement gate server-side, so an expired org can still load it.
  Future<void> loadSubscriptionStatus() async {
    if (!apiEnabled || _api == null) return;
    try {
      final data =
          await _api!.request('GET', '/api/v1/saas/subscription/status');
      _subscriptionStatus =
          data is Map<String, dynamic> ? subscriptionStatusFromApi(data) : null;
      _subscriptionStatusError =
          _subscriptionStatus == null ? 'No subscription on file' : null;
    } on ApiException catch (e) {
      _subscriptionStatusError = e.message;
    } on NetworkException {
      _subscriptionStatusError = 'Server unreachable';
    }
    notifyListeners();
  }

  /// One-shot owner login for billing actions. Returns the owner token or
  /// null; the token is used for a single request and never persisted.
  /// Bad credentials leave the action error null (the dialog shows a generic
  /// message); an unreachable server sets 'Server unreachable' so the dialog
  /// does not blame the credentials.
  Future<String?> loginOwnerForAction(String email, String password) async {
    if (_api == null) return null;
    _subscriptionActionError = null;
    try {
      final data = await _api!.request('POST', '/api/v1/auth/account/login',
          body: {'email': email, 'password': password}, auth: false);
      if (data is! Map<String, dynamic>) return null;
      final t = data['token'];
      final token = (t is String && t.isNotEmpty) ? t : null;
      return token;
    } on ApiException {
      return null;
    } on NetworkException {
      _subscriptionActionError = 'Server unreachable';
      notifyListeners();
      return null;
    }
  }

  Future<RazorpaySubscriptionStart?> startAutoRenew(String ownerToken) async {
    return _ownerBillingCall(ownerToken, '/api/v1/saas/subscription/razorpay',
        (j) => razorpayStartFromApi(j));
  }

  Future<RazorpayManualOrder?> createManualRenewal(String ownerToken) async {
    return _ownerBillingCall(
        ownerToken, '/api/v1/saas/subscription/manual-order',
        (j) => razorpayManualOrderFromApi(j));
  }

  Future<bool> cancelAutoRenew(String ownerToken) async {
    return (await _ownerBillingCall<bool>(
            ownerToken, '/api/v1/saas/subscription/cancel', (_) => true)) ??
        false;
  }

  Future<T?> _ownerBillingCall<T>(
    String ownerToken,
    String path,
    T Function(Map<String, dynamic>) parse,
  ) async {
    if (_api == null) return null;
    _subscriptionActionError = null;
    try {
      final data = await _api!.request('POST', path, token: ownerToken);
      if (data is! Map<String, dynamic>) {
        _subscriptionActionError = 'Unexpected response';
        notifyListeners();
        return null;
      }
      notifyListeners();
      return parse(data);
    } on ApiException catch (e) {
      _subscriptionActionError = e.message;
      notifyListeners();
      return null;
    } on NetworkException {
      _subscriptionActionError = 'Server unreachable';
      notifyListeners();
      return null;
    }
  }

  /// Binds the terminal to an org via its code and loads the org-scoped
  /// outlet/staff lists (device bootstrap). Throws ApiException/NetworkException.
  Future<void> bootstrapOrg(String code) async {
    if (!apiEnabled || _api == null) {
      throw NetworkException('Org setup requires the server connection');
    }
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter the organization code');
    }
    final resp = await _api!.request('POST', '/api/v1/auth/device-options',
        body: {'org_code': trimmed}, auth: false);
    if (resp is! Map) {
      throw const FormatException('Unexpected server response');
    }
    final orgId = (resp['org_id'] ?? '').toString();
    final orgName = (resp['org_name'] ?? '').toString();
    if (orgId.isEmpty) {
      throw const FormatException('Unknown organization code');
    }
    final tenant = TenantInfo(orgCode: trimmed, orgId: orgId, orgName: orgName);

    final outlets = <Outlet>[];
    if (resp['outlets'] is List) {
      for (final o in resp['outlets'] as List) {
        if (o is Map) outlets.add(outletFromApi(o.cast<String, dynamic>()));
      }
    }
    final staff = <Staff>[];
    if (resp['staff'] is List) {
      for (final s in resp['staff'] as List) {
        if (s is Map) staff.add(staffFromApi(s.cast<String, dynamic>()));
      }
    }
    _tenant = tenant;
    await _tenantStore?.save(tenant);
    _outlets
      ..clear()
      ..addAll(outlets);
    _staffList
      ..clear()
      ..addAll(staff.where((s) => s.isActive));
    if (_outlets.isNotEmpty) {
      _currentOutlet = _outlets.first;
    }
    notifyListeners();
    // Narrow the sign-in roster to the chosen outlet.
    unawaited(hydratePublic());
  }

  /// Self-service organization onboarding (SaaS): creates the org + owner
  /// account + 7-day Pro trial + first outlet + admin staff via
  /// POST /api/v1/auth/register, then binds this terminal to the new org
  /// (same hydration as [bootstrapOrg]) so PIN login works immediately.
  /// Returns the org code + one-time admin PIN for the success screen.
  /// Throws ApiException/NetworkException/FormatException on failure.
  Future<RegisterOrgResult> registerOrg({
    required String orgName,
    required String ownerName,
    required String email,
    required String password,
    required String outletName,
    String terminal = 'Counter 1',
  }) async {
    if (!apiEnabled || _api == null) {
      throw NetworkException('Registration requires the server connection');
    }
    final org = orgName.trim();
    final owner = ownerName.trim();
    final mail = email.trim();
    final outlet = outletName.trim();
    final term = terminal.trim().isEmpty ? 'Counter 1' : terminal.trim();
    if (org.isEmpty || owner.isEmpty || mail.isEmpty || outlet.isEmpty) {
      throw const FormatException(
          'Restaurant, owner, email and outlet names are required');
    }
    if (password.length < 8) {
      throw const FormatException('Password must be at least 8 characters');
    }
    final resp = await _api!.request('POST', '/api/v1/auth/register',
        body: {
          'org_name': org,
          'owner_name': owner,
          'email': mail,
          'password': password,
          'outlet_name': outlet,
          'terminal': term,
          'plan_code': 'pro',
        },
        auth: false);
    if (resp is! Map) {
      throw const FormatException('Unexpected server response');
    }
    final result =
        registerOrgResultFromApi(resp.cast<String, dynamic>());
    if (result.orgCode.isEmpty || result.orgId.isEmpty) {
      throw const FormatException('Registration failed. Try again.');
    }
    // Bind the terminal to the freshly provisioned org.
    await bootstrapOrg(result.orgCode);
    return result;
  }

  void _applyLoginEntitlement(Map<String, dynamic> resp) {
    final ent = resp['entitlement'];
    final token = resp['entitlement_token']?.toString();
    _entitlement = entitlementFromServer(
      ent is Map ? ent.cast<String, dynamic>() : null,
      (token == null || token.isEmpty) ? null : token,
    );
    unawaited(_tenantStore?.saveEntitlement(_entitlement!));
  }

  /// One hydrated read. Per-section API errors (e.g. a 404 on settings) are
  /// recorded and skipped; only a full network outage aborts the rest.
  Future<dynamic> _tryRead(String path, Map<String, String> query) async {
    try {
      return await _api!.request('GET', path, query: query);
    } on ApiException catch (e) {
      _lastSyncError = e.message;
      return null;
    }
  }

  /// Re-reads everything for the current outlet from the server.
  Future<void> hydrateOutlet() async {
    if (!apiEnabled || _api == null || _hydrating) return;
    _hydrating = true;
    try {
      await _reload(_allResources);
      _lastSyncAt = DateTime.now();
      _lastSyncError = null;
    } on NetworkException {
      _lastSyncError = 'Server unreachable';
    } finally {
      _hydrating = false;
      notifyListeners();
    }
  }

  static const _allResources = [
    'menu', 'tables', 'orders', 'kots', 'outlet', 'settings', 'shift', 'expenses',
    'customers', 'inventory', 'suppliers', 'purchases', 'shifts', 'dashboard', 'staff',
  ];

  /// Re-reads only the given resources (after a save, or when another
  /// terminal announces a change). Network errors propagate.
  Future<void> _reload(Iterable<String> resources) async {
    final outletId = _currentOutlet.id;
    Map<String, String> q = {'outlet_id': outletId};
    for (final r in resources) {
      switch (r) {
        case 'menu':
          final menu = await _tryRead('/api/v1/menu', q);
          if (menu is Map && menu['menu_items'] is List) {
            _menuItems
              ..clear()
              ..addAll((menu['menu_items'] as List)
                  .whereType<Map>()
                  .map((m) => menuItemFromApi(m.cast<String, dynamic>())));
            _rebuildCategories();
          }
          break;
        case 'tables':
          final tables = await _tryRead('/api/v1/tables', q);
          if (tables is Map && tables['tables'] is List) {
            _tables
              ..clear()
              ..addAll((tables['tables'] as List)
                  .whereType<Map>()
                  .map((t) => tableFromApi(t.cast<String, dynamic>())));
          }
          break;
        case 'orders':
          final orders = await _tryRead(
              '/api/v1/orders', {'outlet_id': outletId, 'limit': '100'});
          if (orders is Map && orders['orders'] is List) {
            _orders
              ..clear()
              ..addAll((orders['orders'] as List)
                  .whereType<Map>()
                  .map((o) => orderFromApi(o.cast<String, dynamic>(), _menuLookup)));
          }
          break;
        case 'kots':
          final kots = await _tryRead('/api/v1/kots', q);
          if (kots is Map && kots['kots'] is List) {
            _kots
              ..clear()
              ..addAll((kots['kots'] as List)
                  .whereType<Map>()
                  .map((k) => kotFromApi(k.cast<String, dynamic>())));
          }
          break;
        case 'outlet':
          final outlet = await _tryRead('/api/v1/outlets/$outletId', q);
          if (outlet is Map && outlet['id'] == outletId) {
            _currentOutlet = outletFromApi(outlet.cast<String, dynamic>());
            final i = _outlets.indexWhere((o) => o.id == outletId);
            if (i >= 0) _outlets[i] = _currentOutlet;
          }
          break;
        case 'settings':
          final settings = await _tryRead('/api/v1/settings', q);
          if (settings is Map) {
            _settings = settingsFromApi(settings.cast<String, dynamic>());
          }
          _settings = _withOutletProfile(_settings);
          break;
        case 'shift':
          final shift = await _tryRead('/api/v1/shifts/current', q);
          if (shift is Map && shift['shift'] is Map) {
            _currentShift = shiftFromApi((shift['shift'] as Map).cast<String, dynamic>());
          } else if (shift is Map) {
            _currentShift = null;
          }
          break;
        case 'expenses':
          final expenses = await _tryRead('/api/v1/expenses', q);
          if (expenses is Map && expenses['expenses'] is List) {
            _expenses
              ..clear()
              ..addAll((expenses['expenses'] as List)
                  .whereType<Map>()
                  .map((e) => expenseFromApi(e.cast<String, dynamic>())));
          }
          break;
        case 'customers':
          final customers = await _tryRead('/api/v1/customers', q);
          if (customers is Map && customers['customers'] is List) {
            _customers
              ..clear()
              ..addAll((customers['customers'] as List)
                  .whereType<Map>()
                  .map((c) => customerFromApi(c.cast<String, dynamic>())));
          }
          break;
        case 'inventory':
          final inventory = await _tryRead('/api/v1/inventory', q);
          if (inventory is Map && inventory['inventory'] is List) {
            _inventory
              ..clear()
              ..addAll((inventory['inventory'] as List)
                  .whereType<Map>()
                  .map((i) => inventoryItemFromApi(i.cast<String, dynamic>())));
          }
          break;
        case 'suppliers':
          final suppliers = await _tryRead('/api/v1/suppliers', q);
          if (suppliers is Map && suppliers['suppliers'] is List) {
            _suppliers
              ..clear()
              ..addAll((suppliers['suppliers'] as List)
                  .whereType<Map>()
                  .map((s) => supplierFromApi(s.cast<String, dynamic>())));
          }
          break;
        case 'purchases':
          final purchases = await _tryRead('/api/v1/purchases', q);
          if (purchases is Map && purchases['purchases'] is List) {
            _purchases
              ..clear()
              ..addAll((purchases['purchases'] as List)
                  .whereType<Map>()
                  .map((p) => purchaseFromApi(p.cast<String, dynamic>())));
          }
          break;
        case 'shifts':
          final shifts = await _tryRead('/api/v1/shifts', q);
          if (shifts is Map && shifts['shifts'] is List) {
            _shiftHistory
              ..clear()
              ..addAll((shifts['shifts'] as List)
                  .whereType<Map>()
                  .map((s) => shiftFromApi(s.cast<String, dynamic>()))
                  .where((s) => s.isClosed));
          }
          break;
        case 'staff':
          // Managers see everyone, including deactivated staff (reactivate).
          if (canManage) {
            final staff = await _tryRead('/api/v1/staff/all', q);
            if (staff is Map && staff['staff'] is List) {
              _staffList
                ..clear()
                ..addAll((staff['staff'] as List)
                    .whereType<Map>()
                    .map((s) => staffFromApi(s.cast<String, dynamic>())));
            }
          }
          break;
        case 'dashboard':
          // Overall revenue dashboard is admin-only — skip for every other role
          // so hydrate never trips a 403 (which would surface as a sync error).
          if (_currentStaff?.role == StaffRole.admin) {
            final dash = await _tryRead('/api/v1/reports/dashboard', q);
            if (dash is Map) {
              _serverDashboard = dashboardReportFromApi(dash.cast<String, dynamic>());
            }
          }
          break;
      }
    }
  }

  /// Best-effort refresh of a few resources; failures are left for the next
  /// full re-read.
  Future<void> _refresh(Iterable<String> resources) async {
    if (!apiEnabled || _api == null || _currentStaff == null) return;
    try {
      await _reload(resources);
    } catch (_) {
      // offline / transient — the reconnect re-read covers it
    }
    notifyListeners();
  }

  /// Test-only: loads a fixed catalog the way a hydrate would. Production
  /// state only ever comes from the server.
  @visibleForTesting
  void loadFixture({
    List<Outlet> outlets = const [],
    List<Staff> staff = const [],
    List<RestaurantTable> tables = const [],
    List<MenuItem> menu = const [],
  }) {
    _outlets
      ..clear()
      ..addAll(outlets);
    if (outlets.isNotEmpty) _currentOutlet = outlets.first;
    _staffList
      ..clear()
      ..addAll(staff);
    _tables
      ..clear()
      ..addAll(tables);
    _menuItems
      ..clear()
      ..addAll(menu);
    _rebuildCategories();
    notifyListeners();
  }

  /// Bills print the outlet's legal identity (address, GSTIN, FSSAI), which
  /// lives on the outlet record, not in settings.
  RestaurantSettings _withOutletProfile(RestaurantSettings s) => s.copyWith(
        restaurantName: s.restaurantName.isEmpty ? _currentOutlet.name : s.restaurantName,
        address: _currentOutlet.address,
        phone: _currentOutlet.phone,
        email: _currentOutlet.email,
        gstin: _currentOutlet.gstin,
        fssai: _currentOutlet.fssai,
      );

  void _rebuildCategories() {
    final cats = _menuItems
        .where((m) => m.outletId == null || m.outletId == _currentOutlet.id)
        .map((m) => m.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    categories
      ..clear()
      ..add('All')
      ..addAll(cats);
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }
  }

  // ---- Op registry: payload → API call ----

  /// Sends a write for the current outlet and completes with `null` once
  /// the server saved it, or with the reason it was not saved (the change is
  /// then undone on screen by re-reading the server). Demo mode: no-op.
  Future<String?> _push(String type, Map<String, dynamic> payload) {
    final sync = _sync;
    if (sync == null) return Future.value(null);
    final orderId = payload['order_id'];
    if (type != 'order.create' && orderId is String) _flushDraft(orderId);
    return sync.push(type, {'outlet_id': _currentOutlet.id, ...payload});
  }

  void _registerOps() {
    final api = _api!;
    final sync = _sync!;
    for (final type in knownOpTypes) {
      sync.register(type, (p) async {
        final req = buildOpRequest(type, p);
        final outletId = (p['outlet_id'] ?? _currentOutlet.id).toString();
        final resp = await api.request(
          req.method,
          req.path,
          query: {'outlet_id': outletId},
          body: req.body,
          idempotencyKey: req.idempotent ? p['__key']?.toString() : null,
        );
        if (resp is! Map) return null;
        final map = resp.cast<String, dynamic>();
        // Refunds answer {order, refunded_paise, ...}; acks want the order.
        if (type == 'order.refund' && map['order'] is Map) {
          return (map['order'] as Map).cast<String, dynamic>();
        }
        return map;
      });
    }
  }

  /// Undoes what the screen showed for a write that was not saved, then
  /// re-reads the outlet (now, or as soon as the connection is back) so the
  /// screen shows exactly what the server has.
  void _onOpRejected(OutboxOp op, ApiException e) {
    final message = e.code == 'offline' ? SyncEngine.offlineMessage : SyncEngine.describeWriteError(e);
    _rejections.insert(0, SyncRejection(op.type, message, DateTime.now()));
    if (_rejections.length > 20) _rejections.removeLast();
    _lastSyncError = message;
    if (!_saveErrors.isClosed) _saveErrors.add('Not saved: $message');
    switch (op.type) {
      case 'order.create':
        final localId = op.payload['local_id']?.toString();
        _orders.removeWhere((o) => o.id == localId);
        for (final t in _tables.where((t) => t.activeOrderId == localId)) {
          t
            ..status = TableStatus.available
            ..activeOrderId = null
            ..currentOrderAmount = 0.0;
        }
        if (_activeOrder?.id == localId) _activeOrder = null;
        break;
      default:
        break;
    }
    notifyListeners();
    // Offline: the re-read happens on reconnect (_onReconnect).
    if (_sync?.online ?? false) _resync();
  }

  void _resync() {
    if (_currentStaff == null) return;
    _hydrating = false;
    unawaited(hydrateOutlet());
  }

  /// The server is reachable again: re-read everything (other terminals may
  /// have changed things meanwhile, and nothing local survives offline).
  void _onReconnect() {
    final waiters = List<Completer<void>>.from(_onlineWaiters);
    _onlineWaiters.clear();
    for (final w in waiters) {
      if (!w.isCompleted) w.complete();
    }
    if (_currentStaff == null) {
      // Booted offline: the PIN screen needs this org's outlets and staff.
      if (_tenant != null) unawaited(hydratePublic());
      if (_pendingRestore) unawaited(_runPendingRestore());
      return;
    }
    _resync();
    _connectRealtime();
  }

  // Navigation — role-driven. The index points into [navDestinations], the
  // canonical ordered destination list for the signed-in role.
  int _currentNavIndex = 0;
  int get currentNavIndex => _currentNavIndex;
  void setNavIndex(int index) {
    final list = navDestinations;
    if (list.isEmpty) return;
    _currentNavIndex = index.clamp(0, list.length - 1);
    notifyListeners();
  }

  /// Role-filtered, ordered destinations. Revenue screens (dashboard/reports)
  /// exist only for Admin; Manager/Cashier get everything else; Waiters get
  /// the order flow only. Kitchen uses a dedicated full-screen KDS instead.
  List<AppDest> get navDestinations {
    final role = _currentStaff?.role;
    switch (role) {
      case StaffRole.admin:
        return const [
          AppDest.dashboard,
          AppDest.runningOrders,
          AppDest.pos,
          AppDest.tables,
          AppDest.kitchen,
          AppDest.transactions,
          AppDest.shiftCash,
          AppDest.expenses,
          AppDest.customers,
          AppDest.inventory,
          AppDest.reports,
          AppDest.settings,
          AppDest.more,
        ];
      case StaffRole.manager:
      case StaffRole.cashier:
        return const [
          AppDest.pos,
          AppDest.runningOrders,
          AppDest.tables,
          AppDest.kitchen,
          AppDest.transactions,
          AppDest.shiftCash,
          AppDest.expenses,
          AppDest.customers,
          AppDest.inventory,
          AppDest.settings,
          AppDest.more,
        ];
      case StaffRole.waiter:
        return const [
          AppDest.tables,
          AppDest.runningOrders,
          AppDest.pos,
          AppDest.more,
        ];
      case StaffRole.kitchen:
        return const [];
      default:
        return const [];
    }
  }

  /// First destination of the role's list (Home for each role).
  AppDest get roleHomeDest =>
      navDestinations.isNotEmpty ? navDestinations.first : AppDest.pos;

  /// True when the signed-in role may see the overall revenue dashboard.
  bool get isAdmin => _currentStaff?.role == StaffRole.admin;

  void goToHome() {
    if (navDestinations.isEmpty) return;
    setNavIndex(0);
  }

  void goToDest(AppDest dest) {
    final i = navDestinations.indexOf(dest);
    if (i < 0) return;
    setNavIndex(i);
  }

  // ---- Attendance (W3): who clocked in when, on this terminal ----
  // Server truth when online (auto clock-in on login, clock-out on logout);
  // the local ledger keeps working offline and until the first hydration.

  final List<AttendanceEntry> _attendance = [];
  List<AttendanceEntry> get attendanceLog => List.unmodifiable(_attendance);

  /// Hydrates the attendance ledger from the server (replaces local rows).
  Future<void> fetchAttendance() async {
    if (!apiEnabled || _api == null || !_sync!.online) return;
    try {
      final data = await _api!.request('GET', '/api/v1/attendance',
          query: {'outlet_id': _currentOutlet.id});
      if (data is! Map || data['attendance'] is! List) return;
      final server = (data['attendance'] as List)
          .whereType<Map>()
          .map((j) => attendanceFromApi(j.cast<String, dynamic>()))
          .toList();
      _attendance
        ..clear()
        ..addAll(server);
      notifyListeners();
    } on NetworkException {
      // offline — keep the local ledger
    } on ApiException {
      // non-fatal read failure
    }
  }

  AttendanceEntry? _openAttendanceFor(String staffId) =>
      _attendance
          .where((a) => a.staffId == staffId && a.clockOut == null)
          .firstOrNull;

  void _markClockIn(String staffId, String name) {
    if (_openAttendanceFor(staffId) != null) return;
    _attendance.insert(
      0,
      AttendanceEntry(
        id: 'att-${DateTime.now().millisecondsSinceEpoch}',
        staffId: staffId,
        staffName: name,
        clockIn: DateTime.now(),
      ),
    );
  }

  void _markClockOut(String staffId) {
    final open = _openAttendanceFor(staffId);
    if (open == null) return;
    open.clockOut = DateTime.now();
  }

  /// Total worked minutes across all closed sessions for a staff member.
  int workedMinutesFor(String staffId) => _attendance
      .where((a) => a.staffId == staffId)
      .fold(0, (sum, a) => sum + a.minutesWorked);

  // Active User / Session
  Staff? _currentStaff;
  Staff? get currentStaff => _currentStaff;

  Outlet _currentOutlet = Outlet.none;

  Outlet get currentOutlet => _currentOutlet;

  final List<Outlet> _outlets = [];
  List<Outlet> get outlets => _outlets;

  void selectOutlet(Outlet outlet) => _switchOutlet(outlet);

  // Staff Directory & Authentication — 5 uniq roles for out-01 + 4 for out-02 (admin org-wide)
  final List<Staff> _staffList = [];
  List<Staff> get staffList => List.unmodifiable(_staffList);

  /// Returns staff eligible for the currently selected outlet.
  /// Waiters can only belong to their single assigned outlet;
  /// other staff roles may be org-wide floaters.
  List<Staff> get currentOutletStaff => List.unmodifiable(
      _staffList.where((s) => s.isActive && s.canAccessOutlet(_currentOutlet.id)));

  /// Active waiters/cashiers eligible to be assigned to tables in the current outlet.
  List<Staff> get currentOutletWaiters =>
      List.unmodifiable(_staffList.where((s) =>
          (s.role == StaffRole.waiter || s.role == StaffRole.cashier) &&
          s.isActive &&
          s.canAccessOutlet(_currentOutlet.id)));

  /// Remembers who is signed in (and on which outlet) so the login survives
  /// app restarts. Cleared only on explicit logout / org rebind. No secrets:
  /// tokens live in OutboxStore, PINs never leave the vault as hashes.
  Future<void> _saveLoginSnapshot() async {
    final staff = _currentStaff;
    if (staff == null) return;
    await _sessionStore?.save(StaffSessionSnapshot(
      staffId: staff.id,
      outletId: _currentOutlet.id,
      outletName: _currentOutlet.name,
      outletTerminal: _currentOutlet.terminal,
    ));
  }

  /// Silent re-login after an app restart: rotates the saved refresh token
  /// and restores the staff + entitlement from the server. Returns true when
  /// a session was restored; false means the PIN screen (or, while the
  /// server is unreachable, the "No connection" screen) stays.
  Future<bool> restoreSavedLogin() async {
    if (!apiEnabled || _api == null) return false;
    final snap = await _sessionStore?.load();
    if (snap == null) return false;
    final outletMatch =
        _outlets.where((o) => o.id == snap.outletId).firstOrNull;
    if (outletMatch != null) {
      _currentOutlet = outletMatch;
    } else if (snap.outletId.isNotEmpty) {
      _currentOutlet = Outlet(
        id: snap.outletId,
        name: snap.outletName.isEmpty ? _currentOutlet.name : snap.outletName,
        address: '',
        terminal: snap.outletTerminal,
        gstin: '',
        fssai: '',
        phone: '',
      );
    }
    // Online only: the server re-checks the session. Without a connection
    // the snapshot stays and the app waits on the "No connection" screen.
    if (!(_sync?.online ?? false)) {
      _markRestorePending();
      return false;
    }
    try {
      final data = await _api!.refreshSessionWithPayload();
      final staffMap = data?['staff'] is Map
          ? (data!['staff'] as Map).cast<String, dynamic>()
          : null;
      if (data == null || staffMap == null) {
        await _sessionStore?.clear();
        return false;
      }
      final serverStaff = staffFromApi(staffMap);
      _currentStaff =
          _staffList.where((s) => s.id == serverStaff.id).firstOrNull ??
              serverStaff;
      _applyLoginEntitlement(data);
      _lastSyncError = null;
    } on NetworkException {
      _markRestorePending();
      return false;
    } catch (_) {
      await _sessionStore?.clear();
      return false;
    }
    // A restored session is a new working session: clock in on the server
    // (no-op when already clocked in).
    unawaited(_api!
        .request('POST', '/api/v1/attendance/clock-in', query: {'outlet_id': _currentOutlet.id}, body: const {})
        .then((_) {}, onError: (_) {}));
    await _loadCurrentShift();
    notifyListeners();
    unawaited(_postLoginSync());
    return true;
  }

  /// A saved login could not be checked because the server was unreachable
  /// at boot; it is retried when the connection is back.
  bool _pendingRestore = false;
  bool get pendingRestore => _pendingRestore;
  final List<Completer<void>> _onlineWaiters = [];

  /// Completes once the server is reachable (right away when it is).
  Future<void> whenOnline() {
    if (!apiEnabled || (_sync?.online ?? false)) return Future.value();
    final c = Completer<void>();
    _onlineWaiters.add(c);
    return c.future;
  }
  Completer<void>? _restoreWait;

  /// Completes once a saved login that was waiting for the connection has
  /// been checked with the server (signed in again, or rejected).
  Future<void> get pendingRestoreDone => _restoreWait?.future ?? Future.value();

  void _markRestorePending() {
    _pendingRestore = true;
    _restoreWait ??= Completer<void>();
  }

  Future<void> _runPendingRestore() async {
    _pendingRestore = false;
    await restoreSavedLogin();
    if (!_pendingRestore) {
      final wait = _restoreWait;
      _restoreWait = null;
      if (wait != null && !wait.isCompleted) wait.complete();
    }
    notifyListeners();
  }

  Future<void> _loadCurrentShift() async {
    try {
      final shift = await _api!
          .request('GET', '/api/v1/shifts/current', query: {'outlet_id': _currentOutlet.id})
          .timeout(const Duration(seconds: 4));
      if (shift is Map && shift['shift'] is Map) {
        _currentShift = shiftFromApi((shift['shift'] as Map).cast<String, dynamic>());
      } else if (shift is Map) {
        _currentShift = null;
      }
    } catch (_) {
      // Offline/slow: the hydrate that follows fills it in.
    }
  }

  /// Server login. Returns false for a wrong PIN, or when the server can't
  /// be reached ([loginError] then says why). Demo mode checks the local
  /// roster.
  Future<bool> loginStaffById(String staffId, String pin) async {
    _loginError = null;
    if (apiEnabled && _api != null) {
      try {
        final resp = await _api!.login(staffId, pin, _currentOutlet.id);
        final serverStaff = resp['staff'] is Map ? (resp['staff'] as Map).cast<String, dynamic>() : null;
        final matched = _staffList.where((s) => s.id == staffId).firstOrNull;
        _currentStaff = matched ?? staffFromApi(serverStaff ?? {});
        _applyLoginEntitlement(resp);
        _lastSyncError = null;
        _pendingRestore = false;
        notifyListeners();
        unawaited(_saveLoginSnapshot());
        // Know whether this outlet already has an open shift before the UI
        // routes (otherwise it asks to open a second one and gets a 409).
        await _loadCurrentShift();
        unawaited(_postLoginSync());
        return true;
      } on NetworkException {
        _loginError = 'No internet connection. Connect to sign in.';
        notifyListeners();
        return false;
      } on ApiException catch (e) {
        if (e.status == 401 || e.status == 403 && e.code != 'forbidden') return false;
        if (e.status >= 500 || e.status == 429) {
          _loginError = SyncEngine.describeWriteError(e);
          notifyListeners();
        }
        return false;
      }
    }
    try {
      final staff = _staffList.firstWhere(
        (s) => s.id == staffId && s.pin == pin && s.isActive,
      );
      _currentStaff = staff;
      _markClockIn(staffId, staff.name);
      notifyListeners();
      unawaited(_saveLoginSnapshot());
      unawaited(_postLoginSync());
      return true;
    } catch (_) {
      return false;
    }
  }

  @Deprecated('Use loginStaffById — PIN alone can match multiple staff')
  bool loginStaff(String pin) {
    try {
      final staff = _staffList.firstWhere((s) => s.pin == pin);
      _currentStaff = staff;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void logout() {
    final leaving = _currentStaff;
    if (apiEnabled && _api != null) {
      // Stop this device receiving the outlet's alerts once nobody is signed in.
      final token = PushNotificationService.instance.fcmToken;
      if (token != null && token.isNotEmpty && (_sync?.online ?? false)) {
        unawaited(_api!.unregisterDeviceToken(token));
      }
      unawaited(_api!.logout());
      unawaited(_realtime?.dispose());
      _realtime = null;
      _api!.session = null;
      _persistSession(null);
    }
    unawaited(_sessionStore?.clear());
    if (leaving != null && !apiEnabled) {
      _markClockOut(leaving.id); // demo mode; the server clocks out on /auth/logout
    }
    _currentStaff = null;
    // Forget pending "order ready" alerts, the open cart and the home
    // position: the next staff member on this terminal starts clean (their
    // running orders come back from the server).
    _readyAlerts.clear();
    _readyAlertTick = 0;
    _currentNavIndex = 0;
    _activeOrder = null;
    _selectedTable = null;
    notifyListeners();
  }

  /// FR-A3 manager gate, checked by the server (POST
  /// /auth/verify-manager-pin). Returns the approving manager, or null.
  Future<Staff?> verifyManagerPin(String pin) async {
    if (apiEnabled && _api != null) {
      try {
        final staffMap = await _api!.verifyManagerPin(pin);
        return staffMap == null ? null : staffFromApi(staffMap);
      } on NetworkException {
        return null;
      } on ApiException {
        return null;
      }
    }
    try {
      return _staffList.firstWhere(
        (s) => s.pin == pin &&
            (s.role == StaffRole.manager || s.role == StaffRole.admin) &&
            s.isActive,
      );
    } catch (_) {
      return null;
    }
  }

  // Shifts
  Shift? _currentShift;
  Shift? get currentShift => _currentShift;
  final List<Shift> _shiftHistory = [];
  List<Shift> get shiftHistory => _shiftHistory;

  /// Opens the drawer for this outlet. Saved on the server first; returns
  /// null when the shift is open, otherwise why not.
  Future<String?> openShift({
    required double openingCash,
    String? notes,
    CashDenomination? denominations,
  }) async {
    if (_sync == null) {
      // Demo mode: no server.
      _currentShift = Shift(
        id: 'SH-${DateTime.now().millisecondsSinceEpoch}',
        staffId: _currentStaff?.id ?? 'st-01',
        staffName: _currentStaff?.name ?? 'Staff',
        startedAt: DateTime.now(),
        openingCash: openingCash,
        openingNotes: notes,
        closingDenominations: denominations,
      );
      notifyListeners();
      return null;
    }
    final error = await _push('shift.open', {
      'opening_paise': toPaise(openingCash),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (denominations != null) 'denominations': denominationsToApi(denominations),
    });
    if (error != null && _currentShift == null) {
      // Someone else may have opened it meanwhile (409): show theirs.
      await _refresh(['shift']);
      if (_currentShift != null) return null;
    }
    return error;
  }

  /// Closes the drawer. Saved on the server first, so a Z-report fetched
  /// afterwards reflects the closed shift. Returns null when closed,
  /// otherwise why not (the shift then stays open).
  Future<String?> closeShift({
    required double actualCash,
    String? notes,
    CashDenomination? denominations,
  }) async {
    final open = _currentShift;
    if (open == null) return 'No open shift';
    if (_sync == null) {
      open
        ..closedAt = DateTime.now()
        ..actualCashClosed = actualCash
        ..closingNotes = notes
        ..closingDenominations = denominations
        ..isClosed = true;
      _shiftHistory.insert(0, open);
      _currentShift = null;
      notifyListeners();
      return null;
    }
    final error = await _push('shift.close', {
      'counted_paise': toPaise(actualCash),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (denominations != null) 'denominations': denominationsToApi(denominations),
    });
    if (error == null) {
      _currentShift = null; // applyServerTruth already moved it to history
      notifyListeners();
    }
    return error;
  }

  // Cash In / Out
  final List<CashTransaction> _cashTransactions = [];
  List<CashTransaction> get cashTransactions => _cashTransactions;

  /// Reads the cash-move ledger from the server (all shifts of the outlet).
  Future<void> fetchCashMoves() async {
    if (!apiEnabled || _api == null || !_sync!.online) return;
    try {
      final data = await _api!.request('GET', '/api/v1/cash-moves',
          query: {'outlet_id': _currentOutlet.id});
      if (data is! Map || data['cash_moves'] is! List) return;
      _cashTransactions
        ..clear()
        ..addAll((data['cash_moves'] as List)
            .whereType<Map>()
            .map((j) => cashMoveFromApi(j.cast<String, dynamic>())));
      notifyListeners();
    } on NetworkException {
      // offline: the "No connection" screen covers it
    } on ApiException {
      // non-fatal read failure
    }
  }

  void addCashIn({required double amount, required String reason, String? reference, DateTime? at}) {
    if (amount <= 0) return;
    final when = at ?? DateTime.now();
    final tx = CashTransaction(
      id: 'CIN-${DateTime.now().millisecondsSinceEpoch}',
      type: CashFlowType.cashIn,
      amount: amount,
      reason: reason,
      reference: reference,
      timestamp: when,
      staffName: _currentStaff?.name ?? 'Staff',
    );
    _cashTransactions.insert(0, tx);
    // Every recorded move counts toward the open shift — matching the server,
    // which books each cash move into the current shift regardless of the
    // ledger timestamp (the `at` date is display/audit only).
    _currentShift?.cashIn += amount;
    notifyListeners();
    _push('cash.move', {
      'type': 'cash_in',
      'amount_paise': toPaise(amount),
      'reason': reason,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      'at': when.toUtc().toIso8601String(),
    });
  }

  void addCashOut({required double amount, required String reason, String? reference, DateTime? at}) {
    if (amount <= 0) return;
    final when = at ?? DateTime.now();
    final tx = CashTransaction(
      id: 'COUT-${DateTime.now().millisecondsSinceEpoch}',
      type: CashFlowType.cashOut,
      amount: amount,
      reason: reason,
      reference: reference,
      timestamp: when,
      staffName: _currentStaff?.name ?? 'Staff',
    );
    _cashTransactions.insert(0, tx);
    _currentShift?.cashOut += amount;
    notifyListeners();
    _push('cash.move', {
      'type': 'cash_out',
      'amount_paise': toPaise(amount),
      'reason': reason,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
      'at': when.toUtc().toIso8601String(),
    });
  }

  // Tables
  String _selectedFloor = 'All';
  String get selectedFloor => _selectedFloor;
  void setFloor(String floor) {
    _selectedFloor = floor;
    notifyListeners();
  }

  static const List<String> tableStatusFilters = [
    'All',
    'Available',
    'Occupied',
    'Billing',
    'Reserved',
    'Cleaning',
  ];
  String _selectedTableStatus = 'All';
  String get selectedTableStatus => _selectedTableStatus;
  void setTableStatus(String status) {
    _selectedTableStatus = status;
    notifyListeners();
  }

  final List<RestaurantTable> _tables = [];
  List<RestaurantTable> get tables => List.unmodifiable(_tables);

  List<RestaurantTable> get filteredTables {
    final floorMatch = _selectedFloor == 'All'
        ? _tables
        : _tables.where((t) => t.floor == _selectedFloor);
    if (_selectedTableStatus == 'All') return List.unmodifiable(floorMatch);
    return List.unmodifiable(
      floorMatch.where((t) => t.statusLabel == _selectedTableStatus),
    );
  }

  /// Explicitly marks a reserved/cleaning table available again.
  void markTableAvailable(RestaurantTable table) {
    final t = _tables.firstWhere(
      (x) => x.id == table.id,
      orElse: () => table,
    );
    if (t.status == TableStatus.available) {
      notifyListeners();
      return;
    }
    t.status = TableStatus.available;
    if (_selectedTable?.id == t.id) {
      _selectedTable = null;
      _activeOrder = null;
    }
    notifyListeners();
    _push('table.status', {
      'table_id': t.id,
      'status': tableStatusToApi(TableStatus.available),
    });
  }

  RestaurantTable? _selectedTable;
  RestaurantTable? get selectedTable => _selectedTable;

  void selectTable(RestaurantTable table) {
    _selectedTable = table;
    // Check if table has an active order
    if (table.activeOrderId != null) {
      _activeOrder = _orders.where((o) => o.id == table.activeOrderId).firstOrNull ??
          _createNewOrderForTable(table);
    } else {
      _activeOrder = _createNewOrderForTable(table);
    }
    notifyListeners();
  }

  RestaurantOrder _createNewOrderForTable(RestaurantTable table) {
    _orderCounter++;
    final waiterId = _currentStaff?.id;
    final waiterName = table.assignedWaiter ?? _currentStaff?.name;
    if (table.assignedWaiter == null && _currentStaff?.role == StaffRole.waiter) {
      table.assignedWaiter = _currentStaff?.name;
    }
    final order = RestaurantOrder(
      id: 'ord-${DateTime.now().millisecondsSinceEpoch}',
      orderNumber: 'New #$_orderCounter',
      orderType: OrderType.dineIn,
      tableId: table.id,
      tableNumber: table.tableNumber,
      createdAt: DateTime.now(),
      waiterId: waiterId,
      waiterName: waiterName,
      guestCount: table.guestCount > 0 ? table.guestCount : 2,
      items: [],
      taxPercent: _settings.gstPercentage,
      isTaxInclusive: _settings.isGstInclusive,
    );
    _pushOrderCreate(order);
    return order;
  }

  /// Orders opened on this terminal but not yet sent to the server. A table
  /// tap only opens a draft; the server order is created with the first real
  /// write (item, guest details, KOT, payment), so browsing tables or
  /// cancelling the guest dialog never leaves ghost orders behind.
  final Set<String> _draftOrders = {};

  void _pushOrderCreate(RestaurantOrder order) => _draftOrders.add(order.id);

  /// Sends the deferred order.create for [orderId] (with the order's latest
  /// guest/customer details) ahead of the op that depends on it.
  void _flushDraft(String orderId) {
    if (!_draftOrders.remove(orderId)) return;
    final order = _activeOrder?.id == orderId
        ? _activeOrder
        : _orders.where((o) => o.id == orderId).firstOrNull;
    if (order != null) _sendOrderCreate(order);
  }

  void _sendOrderCreate(RestaurantOrder order) {
    _push('order.create', {
      'local_id': order.id,
      'type': orderTypeToApi(order.orderType),
      if (order.tableId != null) 'table_id': order.tableId,
      if (order.customerName != null && order.customerName!.isNotEmpty)
        'customer_name': order.customerName,
      if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
        'customer_phone': order.customerPhone,
      if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty)
        'delivery_address': order.deliveryAddress,
      if (order.waiterId != null && order.waiterId!.isNotEmpty)
        'waiter_id': order.waiterId,
      if (order.waiterName != null && order.waiterName!.isNotEmpty)
        'waiter_name': order.waiterName,
      'guest_count': order.guestCount > 0 ? order.guestCount : 1,
      if (order.orderNote != null && order.orderNote!.isNotEmpty)
        'order_note': order.orderNote,
    });
  }

  RestaurantOrder? _ownerOf(OrderItem item) {
    if ((_activeOrder?.items.contains(item)) ?? false) return _activeOrder;
    for (final o in _orders) {
      if (o.items.contains(item)) return o;
    }
    return null;
  }

  void _pushAddItem(RestaurantOrder order, OrderItem item) {
    _push('order.add_item', {
      'order_id': order.id,
      'local_item_id': item.id,
      'menu_item_id': item.menuItem.id,
      if (item.selectedVariant != null) 'variant_id': item.selectedVariant!.id,
      'quantity': item.quantity,
      if (item.itemNote != null && item.itemNote!.isNotEmpty) 'note': item.itemNote,
      'modifiers': item.selectedModifiers.where((m) => m.isSelected).map((m) => m.id).toList(),
    });
  }

  void _pushItemQty(RestaurantOrder order, OrderItem item) {
    _push('item.qty', {
      'order_id': order.id,
      'item_id': item.id,
      'quantity': item.quantity,
    });
  }

  void moveTable(String fromTableId, String toTableId) {
    final fromTable = _tables.where((t) => t.id == fromTableId).firstOrNull;
    final toTable = _tables.where((t) => t.id == toTableId).firstOrNull;
    if (fromTable == null || toTable == null || fromTable.id == toTable.id) return;

    toTable.status = TableStatus.occupied;
    toTable.activeOrderId = fromTable.activeOrderId;
    toTable.currentOrderAmount = fromTable.currentOrderAmount;
    toTable.runningMinutes = fromTable.runningMinutes;
    toTable.guestCount = fromTable.guestCount;
    toTable.assignedWaiter = fromTable.assignedWaiter;

    fromTable.status = TableStatus.available;
    fromTable.activeOrderId = null;
    fromTable.currentOrderAmount = 0.0;
    fromTable.runningMinutes = 0;
    fromTable.guestCount = 0;
    fromTable.assignedWaiter = null;

    if (_activeOrder != null && _activeOrder!.tableId == fromTableId) {
      _selectedTable = toTable;
    }
    notifyListeners();
    _push('table.move', {
      'from_table_id': fromTableId,
      'to_table_id': toTableId,
    });
  }

  void mergeTables(String primaryTableId, String secondaryTableId) {
    final primary = _tables.where((t) => t.id == primaryTableId).firstOrNull;
    final secondary = _tables.where((t) => t.id == secondaryTableId).firstOrNull;
    if (primary == null || secondary == null || primary.id == secondary.id) return;

    // Re-home the secondary table's active order onto the primary so no
    // order is orphaned by the merge.
    if (secondary.activeOrderId != null) {
      final orphan = _orders.where((o) => o.id == secondary.activeOrderId).firstOrNull;
      if (orphan != null) {
        orphan.tableId = primary.id;
        orphan.tableNumber = primary.tableNumber;
        if (primary.activeOrderId == null) {
          primary.activeOrderId = orphan.id;
          primary.currentOrderAmount = orphan.grandTotal;
        }
      }
      secondary.activeOrderId = null;
      secondary.currentOrderAmount = 0.0;
    }
    secondary.mergedWithTableId = primary.id;
    secondary.status = TableStatus.occupied;
    notifyListeners();
    _push('table.merge', {
      'primary_table_id': primaryTableId,
      'secondary_table_id': secondaryTableId,
    });
  }

  void unmergeTable(String tableId) {
    final table = _tables.where((t) => t.id == tableId).firstOrNull;
    if (table == null) return;
    table.mergedWithTableId = null;
    if (table.activeOrderId == null) {
      table.status = TableStatus.available;
    }
    notifyListeners();
    _push('table.unmerge', {'table_id': tableId});
  }

  void assignWaiterToTable(String tableId, String waiterName) {
    final table = _tables.where((t) => t.id == tableId).firstOrNull;
    if (table == null) return;
    final waiter = _staffList.where((s) => s.name == waiterName).firstOrNull;
    table.assignedWaiter = waiterName;
    if (_activeOrder != null && _activeOrder!.tableId == tableId) {
      _activeOrder!.waiterName = waiterName;
      if (waiter != null && !_draftOrders.contains(_activeOrder!.id)) {
        _push('order.patch', {'order_id': _activeOrder!.id, 'waiter_id': waiter.id});
      }
    }
    notifyListeners();
    if (waiter != null) _push('table.patch', {'table_id': tableId, 'waiter_id': waiter.id});
  }

  // Menu & Catalog
  String _selectedCategory = 'All';
  String get selectedCategory => _selectedCategory;
  void setCategory(String cat) {
    _selectedCategory = cat;
    notifyListeners();
  }

  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  bool _filterVegOnly = false;
  bool get filterVegOnly => _filterVegOnly;
  void toggleVegOnly() {
    _filterVegOnly = !_filterVegOnly;
    notifyListeners();
  }

  final List<String> categories = ['All'];

  final List<MenuItem> _menuItems = [];
  List<MenuItem> get menuItems => List.unmodifiable(
      _menuItems.where((m) => m.outletId == null || m.outletId == _currentOutlet.id));

  List<MenuItem> get filteredMenuItems {
    return menuItems.where((item) {
      if (_selectedCategory != 'All' && item.category != _selectedCategory) {
        return false;
      }
      if (_filterVegOnly && !item.isVeg) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = item.name.toLowerCase().contains(q);
        final matchCat = item.category.toLowerCase().contains(q);
        if (!matchName && !matchCat) return false;
      }
      return true;
    }).toList();
  }

  // Active Order / Cart State
  // Terminal-local label until the server assigns the real order number.
  int _orderCounter = 0;
  RestaurantOrder? _activeOrder;
  RestaurantOrder? get activeOrder => _activeOrder;

  RestaurantOrder? orderById(String id) {
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Order type for the next order started without a table (POS header).
  OrderType _newOrderType = OrderType.takeaway;
  OrderType get newOrderType => _newOrderType;

  /// Switches the counter order type. An open table-less order that has not
  /// been sent anywhere yet is converted in place (charges re-defaulted).
  void setNewOrderType(OrderType type, {String? customerPhone, String? address}) {
    if (type == OrderType.dineIn) return; // dine-in starts from a table
    _newOrderType = type;
    final o = _activeOrder;
    if (o != null && o.tableId == null && _draftOrders.contains(o.id)) {
      final keepItems = o.items;
      _draftOrders.remove(o.id);
      startNewOrder(type, customerPhone: customerPhone, address: address);
      _activeOrder!.items.addAll(keepItems);
      return;
    }
    if (o != null && o.tableId == null && o.items.isEmpty && !o.isClosed) {
      // Already on the server: cancel it there instead of leaving it open.
      _orders.removeWhere((x) => x.id == o.id);
      _push('order.cancel', {'order_id': o.id, 'reason': 'Order type changed'});
      startNewOrder(type, customerPhone: customerPhone, address: address);
      return;
    }
    notifyListeners();
  }

  void startNewOrder(OrderType type, {String? customerName, String? customerPhone, String? address}) {
    _orderCounter++;
    // Mirror the outlet settings defaults (same rules the server applies on
    // order create) so offline-created orders bill identically once synced.
    _activeOrder = RestaurantOrder(
      id: 'ord-${DateTime.now().millisecondsSinceEpoch}',
      orderNumber: 'New #$_orderCounter',
      orderType: type,
      createdAt: DateTime.now(),
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: address,
      waiterId: _currentStaff?.id,
      waiterName: _currentStaff?.name,
      items: [],
      taxPercent: _settings.gstPercentage,
      isTaxInclusive: _settings.isGstInclusive,
      packagingCharge: type == OrderType.takeaway || type == OrderType.delivery
          ? _settings.defaultPackagingCharge
          : 0.0,
      deliveryCharge: type == OrderType.delivery ? _settings.defaultDeliveryCharge : 0.0,
    );
    notifyListeners();
    _pushOrderCreate(_activeOrder!);
  }

  void addToCart(
    MenuItem item, {
    ProductVariant? variant,
    List<ModifierItem> modifiers = const [],
    String? note,
    int quantity = 1,
  }) {
    if (_activeOrder == null) {
      // No table picked: a counter sale. Dine-in always needs a table.
      startNewOrder(_newOrderType == OrderType.dineIn ? OrderType.takeaway : _newOrderType);
    }
    if (quantity <= 0) return;

    // Check if same item with same variant and modifiers exists.
    // itemNote participates in the identity so different cooking notes
    // don't merge into one line (and lose a note).
    // Never merge into a line already fired to the kitchen: the added quantity
    // must stay unsent so it shows up for the next KOT instead of silently
    // riding along on an item the kitchen already cooked.
    final existingIndex = _activeOrder!.items.indexWhere(
      (i) =>
          !i.isCancelled &&
          !i.isKOTSent &&
          i.menuItem.id == item.id &&
          i.itemNote == note &&
          i.selectedVariant?.id == variant?.id &&
          _areModifiersIdentical(i.selectedModifiers, modifiers),
    );

    if (existingIndex != -1) {
      _activeOrder!.items[existingIndex].quantity += quantity;
      _pushItemQty(_activeOrder!, _activeOrder!.items[existingIndex]);
    } else {
      final newItem = OrderItem(
        id: 'item-${DateTime.now().millisecondsSinceEpoch}-${_activeOrder!.items.length}',
        menuItem: item,
        selectedVariant: variant,
        selectedModifiers: modifiers.map((m) => m.copy()).toList(),
        quantity: quantity,
        itemNote: note,
        isKOTSent: false,
      );
      _activeOrder!.items.add(newItem);
      _pushAddItem(_activeOrder!, newItem);
    }
    notifyListeners();
  }

  bool _areModifiersIdentical(List<ModifierItem> a, List<ModifierItem> b) {
    if (a.length != b.length) return false;
    final aIds = a.map((m) => m.id).toSet();
    final bIds = b.map((m) => m.id).toSet();
    return aIds.containsAll(bIds);
  }

  void incrementItem(OrderItem item) {
    item.quantity += 1;
    final owner = _ownerOf(item);
    if (owner != null) _pushItemQty(owner, item);
    notifyListeners();
  }

  void decrementItem(OrderItem item, {String? managerPin}) {
    if (item.quantity > 1) {
      item.quantity -= 1;
      final owner = _ownerOf(item);
      if (owner != null) _pushItemQty(owner, item);
    } else {
      final owner = _ownerOf(item);
      _activeOrder?.items.remove(item);
      if (owner != null) {
        _push('item.qty', {
          'order_id': owner.id,
          'item_id': item.id,
          'quantity': 0,
          // FR-A3: dropping a KOT-sent line needs manager authorization.
          if (item.isKOTSent && managerPin != null && managerPin.isNotEmpty)
            'manager_pin': managerPin,
        });
      }
    }
    notifyListeners();
  }

  void removeItem(OrderItem item, {String? managerPin}) {
    final owner = _ownerOf(item);
    _activeOrder?.items.remove(item);
    if (owner != null) {
      _push('item.qty', {
        'order_id': owner.id,
        'item_id': item.id,
        'quantity': 0,
        // FR-A3: dropping a KOT-sent line needs manager authorization.
        if (item.isKOTSent && managerPin != null && managerPin.isNotEmpty)
          'manager_pin': managerPin,
      });
    }
    notifyListeners();
  }

  void setOrderNote(String note) {
    if (_activeOrder != null) {
      _activeOrder!.orderNote = note;
      notifyListeners();
      _push('order.patch', {
        'order_id': _activeOrder!.id,
        'order_note': note,
      });
    }
  }

  void setGuestDetails({required int count, String? customerName, String? customerPhone, String? waiter}) {
    if (_activeOrder != null) {
      _activeOrder!.guestCount = count;
      if (customerName != null) _activeOrder!.customerName = customerName;
      if (customerPhone != null && customerPhone.trim().isNotEmpty) {
        _activeOrder!.customerPhone = customerPhone.trim();
      }
      final waiterStaff = waiter == null
          ? null
          : _staffList.where((s) => s.name == waiter).firstOrNull;
      if (waiter != null) {
        _activeOrder!.waiterName = waiter;
        _activeOrder!.waiterId = waiterStaff?.id ?? _activeOrder!.waiterId;
      }
      notifyListeners();
      if (_draftOrders.contains(_activeOrder!.id)) {
        // Not on the server yet: the create carries these details.
        _flushDraft(_activeOrder!.id);
        return _syncTableGuests(count, waiter);
      }
      _push('order.patch', {
        'order_id': _activeOrder!.id,
        'guest_count': count,
        if (waiterStaff != null) 'waiter_id': waiterStaff.id,
        if (customerName != null && customerName.isNotEmpty) 'customer_name': customerName,
        if (customerPhone != null && customerPhone.trim().isNotEmpty)
          'customer_phone': customerPhone.trim(),
      });
    } else {
      notifyListeners();
    }
    _syncTableGuests(count, waiter);
  }

  void _syncTableGuests(int count, String? waiter) {
    final table = _selectedTable;
    if (table == null) return;
    table.guestCount = count;
    if (waiter != null) table.assignedWaiter = waiter;
    final waiterId = waiter == null ? null : _staffList.where((s) => s.name == waiter).firstOrNull?.id;
    _push('table.patch', {
      'table_id': table.id,
      'guest_count': count,
      if (waiterId != null) 'waiter_id': waiterId,
    });
  }

  // KOT System
  int _kotCounter = 0;
  final List<KitchenOrderTicket> _kots = [];
  // Strict outlet isolation: the KDS only ever shows this terminal's outlet.
  // Tickets without an outlet (legacy) are hidden, never shown cross-outlet.
  List<KitchenOrderTicket> get kots => List.unmodifiable(
      _kots.where((k) => k.outletId == _currentOutlet.id));

  KitchenOrderTicket? sendKOT() {
    if (_activeOrder == null || _activeOrder!.items.isEmpty) return null;

    final unsentItems = _activeOrder!.items.where((i) => !i.isKOTSent && !i.isCancelled).toList();
    if (unsentItems.isEmpty) return null;

    _kotCounter++;
    final kot = KitchenOrderTicket(
      id: 'kot-${DateTime.now().millisecondsSinceEpoch}',
      outletId: _currentOutlet.id,
      kotNumber: 'KOT (sending #$_kotCounter)',
      orderId: _activeOrder!.id,
      tableNumber: _activeOrder!.tableNumber ?? _selectedTable?.tableNumber,
      orderType: _activeOrder!.orderType,
      waiterName: _activeOrder!.waiterName ?? _currentStaff?.name ?? 'Staff',
      createdAt: DateTime.now(),
      items: unsentItems.map((i) => i.copy()).toList(),
      specialInstructions: _activeOrder!.orderNote,
      status: KOTStatus.newTicket,
      // Optimistic write: the number above is a terminal-local guess until the
      // server ack adopts its authoritative KOT number.
      pendingServerAck: true,
    );

    _kots.insert(0, kot);

    // Mark items as sent
    for (var i in unsentItems) {
      i.isKOTSent = true;
    }

    // Update table & order status
    _activeOrder!.status = OrderStatus.preparing;
    if (_selectedTable != null) {
      _selectedTable!.status = TableStatus.occupied;
      _selectedTable!.activeOrderId = _activeOrder!.id;
      _selectedTable!.currentOrderAmount = _activeOrder!.grandTotal;
      _selectedTable!.runningMinutes = 1;
    }

    // Add to running orders list if not present
    if (!_orders.any((o) => o.id == _activeOrder!.id)) {
      _orders.insert(0, _activeOrder!);
    }

    notifyListeners();
    _push('kot.fire', {'order_id': kot.orderId, 'local_kot_id': kot.id});
    if (_settings.autoPrintKOT) {
      _printKot(kot);
    }
    return kot;
  }

  void updateKOTStatus(String kotId, KOTStatus newStatus) {
    final kot = _kots.where((k) => k.id == kotId).firstOrNull;
    if (kot == null) return;
    // Strict outlet isolation: never mutate another outlet's ticket, even if
    // one leaked into the local list before the guards ran.
    if (kot.outletId.isNotEmpty && kot.outletId != _currentOutlet.id) return;
    final prevStatus = kot.status;
    kot.status = newStatus;
    // Serving closes the floor's interest in this ticket — drop its ready
    // banner so the waiter's alert list matches the KOT board.
    if (newStatus == KOTStatus.served) {
      _readyAlerts.removeWhere((k) => k.id == kotId);
    }
    notifyListeners();
    _push('kot.status', {
      'kot_id': kotId,
      'status': kotStatusToApi(newStatus),
    });
    _maybeFireReadyAlert(previous: prevStatus, kot: kot);
  }

  // ---- In-app "order ready" alerts for the assigned waiter ----
  // Fired once per KOT the moment it flips to `ready`, on the terminal whose
  // signed-in staff is the ticket's waiter/captain (realtime SSE path and the
  // kitchen terminal's own local transition both land here).

  final List<KitchenOrderTicket> _readyAlerts = [];
  List<KitchenOrderTicket> get readyAlerts => List.unmodifiable(_readyAlerts);
  int get readyAlertCount => _readyAlerts.length;
  int _readyAlertTick = 0;

  /// Monotonic counter bumped on every new alert (sound trigger for UI).
  int get readyAlertTick => _readyAlertTick;

  void acknowledgeReadyKot(String kotId) {
    _readyAlerts.removeWhere((k) => k.id == kotId);
    notifyListeners();
  }

  void dismissAllReadyAlerts() {
    if (_readyAlerts.isEmpty) return;
    _readyAlerts.clear();
    notifyListeners();
  }

  /// Cooked tickets waiting to be carried to the table. Waiters see only their
  /// own tickets (never another waiter's); manager/cashier/admin see the whole
  /// outlet so they can cover any table. Outlet isolation is already applied
  /// by [kots].
  List<KitchenOrderTicket> get readyToServe {
    final ready = kots.where((k) => k.status == KOTStatus.ready);
    final me = _currentStaff;
    if (me != null && me.role == StaffRole.waiter) {
      return ready.where((k) => k.waiterName == me.name).toList();
    }
    return ready.toList();
  }

  void _maybeFireReadyAlert({required KOTStatus? previous, required KitchenOrderTicket kot}) {
    if (previous == KOTStatus.ready || kot.status != KOTStatus.ready) return;
    final me = _currentStaff;
    if (me == null || me.role == StaffRole.kitchen) return;
    if (kot.waiterName != me.name) return;
    if (_readyAlerts.any((k) => k.id == kot.id)) return;
    _readyAlerts.add(kot);
    if (_readyAlerts.length > 20) {
      _readyAlerts.removeRange(0, _readyAlerts.length - 20);
    }
    _readyAlertTick++;
    notifyListeners();
  }

  // Running Orders
  final List<RestaurantOrder> _orders = [];
  List<RestaurantOrder> get orders => List.unmodifiable(_orders);

  /// Returns active running orders. For staff logged in as [StaffRole.waiter],
  /// this is scoped strictly to orders assigned to them or their tables.
  List<RestaurantOrder> get runningOrders {
    final active = _orders.where((o) => o.status != OrderStatus.completed && o.status != OrderStatus.cancelled);
    final me = _currentStaff;
    if (me != null && me.role == StaffRole.waiter) {
      return active.where((o) => isOrderForWaiter(o, me)).toList();
    }
    return active.toList();
  }

  bool isOrderForWaiter(RestaurantOrder o, Staff waiter) {
    final waiterId = waiter.id.toLowerCase().trim();
    final waiterName = waiter.name.toLowerCase().trim();

    if (o.waiterId != null && o.waiterId!.toLowerCase().trim() == waiterId) {
      return true;
    }
    if (o.waiterName != null && o.waiterName!.toLowerCase().trim() == waiterName) {
      return true;
    }
    if (o.tableId != null) {
      final table = _tables.where((t) => t.id == o.tableId).firstOrNull;
      if (table?.assignedWaiter != null) {
        final assigned = table!.assignedWaiter!.toLowerCase().trim();
        if (assigned == waiterName || assigned == waiterId) {
          return true;
        }
      }
    }
    return false;
  }

  /// Paid bills, including ones later refunded (they stay on record).
  List<RestaurantOrder> get completedTransactions => _orders
      .where((o) => o.status == OrderStatus.completed || o.status == OrderStatus.refunded)
      .toList();

  void openRunningOrder(RestaurantOrder order) {
    _activeOrder = order;
    if (order.tableId != null) {
      _selectedTable = _tables.where((t) => t.id == order.tableId).firstOrNull;
    }
    notifyListeners();
  }

  // Item Cancellation with Reason & Audit
  void cancelItemFromOrder({
    required String orderId,
    required String itemId,
    required String reason,
    String? managerPin,
  }) {
    final order = _orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) return;
    final item = order.items.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;
    item.isCancelled = true;
    item.cancelReason = reason;

    if (order.tableId != null) {
      final table = _tables.where((t) => t.id == order.tableId).firstOrNull;
      if (table != null) table.currentOrderAmount = order.grandTotal;
    }
    notifyListeners();
    _push('item.cancel', {
      'order_id': orderId,
      'item_id': itemId,
      'reason': reason,
      // FR-A3: required server-side when the item's KOT already fired.
      if (managerPin != null && managerPin.isNotEmpty) 'manager_pin': managerPin,
    });
  }

  // Billing & Adjustments
  void applyDiscount({double? percent, double? amount, String? reason, String? managerPin}) {
    if (_activeOrder == null) return;
    if (percent != null) {
      _activeOrder!.discountPercent = percent.clamp(0.0, 100.0);
      _activeOrder!.discountAmount = 0.0;
    } else if (amount != null) {
      _activeOrder!.discountAmount =
          amount.clamp(0.0, _activeOrder!.subtotal);
      _activeOrder!.discountPercent = 0.0;
    }
    _activeOrder!.discountReason = reason;
    notifyListeners();
    _push('order.patch', {
      'order_id': _activeOrder!.id,
      // One or the other: the server refuses both in one request.
      if (percent != null)
        'discount_percent': percent.clamp(0.0, 100.0)
      else if (amount != null)
        'discount_paise': toPaise(_activeOrder!.discountAmount),
      'discount_reason': reason ?? '',
      // FR-A3: server re-verifies the manager gate above its thresholds.
      if (managerPin != null && managerPin.isNotEmpty) 'manager_pin': managerPin,
    });
  }

  void addCharges({double? serviceCharge, double? packaging, double? delivery}) {
    if (_activeOrder == null) return;
    if (serviceCharge != null && serviceCharge >= 0) {
      _activeOrder!.serviceCharge = serviceCharge;
    }
    if (packaging != null && packaging >= 0) {
      _activeOrder!.packagingCharge = packaging;
    }
    if (delivery != null && delivery >= 0) {
      _activeOrder!.deliveryCharge = delivery;
    }
    notifyListeners();
    _push('order.patch', {
      'order_id': _activeOrder!.id,
      if (serviceCharge != null && serviceCharge >= 0)
        'service_charge_paise': toPaise(serviceCharge),
      if (packaging != null && packaging >= 0)
        'packaging_charge_paise': toPaise(packaging),
      if (delivery != null && delivery >= 0)
        'delivery_charge_paise': toPaise(delivery),
    });
  }

  // Payment Execution & Receipt

  /// Settles the active order. The payment is sent to the server first and
  /// nothing changes on screen until the server confirmed it; the result
  /// then carries the paid order (with the server's invoice number) and the
  /// receipt prints. On failure [PaymentResult.error] says why and the order
  /// stays open. Split tender: every leg must be non-negative and cover the
  /// bill; the cash leg may receive more (change). Credit needs
  /// [creditCustomerId].
  Future<PaymentResult> completePayment({
    required String paymentMethod,
    required double amountPaid,
    List<({String method, double amount})>? splits,
    double? cashTendered,
    String? reference,
    String? creditCustomerId,
  }) async {
    const invalid = PaymentResult.failed('Payment does not cover the bill');
    final active = _activeOrder;
    if (active == null) return const PaymentResult.failed('No open order');
    final due = active.grandTotal;
    if (amountPaid + 0.005 < due) return invalid;

    final legs = splits ??
        <({String method, double amount})>[(method: paymentMethod, amount: due)];
    double allocated = 0;
    double cashLeg = 0;
    for (final leg in legs) {
      if (leg.amount < -0.005) return invalid;
      allocated += leg.amount;
      if (PaymentMethodX.fromLabel(leg.method) == PaymentMethod.cash) cashLeg += leg.amount;
    }
    if (allocated + 0.005 < due || allocated > amountPaid + 0.005) return invalid;
    if (splits != null && cashTendered != null && cashTendered + 0.005 < cashLeg) {
      return const PaymentResult.failed('Cash received is less than the cash part');
    }
    final isCredit = PaymentMethodX.fromLabel(paymentMethod) == PaymentMethod.credit;
    if (isCredit && (creditCustomerId == null || creditCustomerId.isEmpty)) {
      return const PaymentResult.failed('Choose the customer for a credit bill');
    }

    final error = await _push('order.pay', {
      'order_id': active.id,
      'method': paymentMethodToApi(splits != null && splits.length > 1
          ? legs.first.method
          : paymentMethod),
      'amount_received_paise': toPaise(amountPaid),
      if (splits != null && splits.length > 1)
        'splits': [
          for (final leg in splits)
            {
              'method': paymentMethodToApi(leg.method),
              'amount_paise': toPaise(leg.amount),
            }
        ],
      if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
      if (isCredit) 'customer_id': creditCustomerId,
    });
    if (error != null) return PaymentResult.failed(error);
    if (_sync == null) _settleLocally(active, paymentMethod, legs, reference);

    // Saved. applyServerTruth already replaced the order with the server's
    // copy (status, invoice number, tender legs).
    final serverId = _sync?.resolveId(active.id) ?? active.id;
    final paid = _orders.where((o) => o.id == serverId || o.id == active.id).firstOrNull ?? active;
    // What the customer handed over (incl. change) is only known here.
    paid.totalPaid = splits == null ? amountPaid : allocated;
    if (paid.tableId != null) {
      final table = _tables.where((t) => t.id == paid.tableId).firstOrNull;
      if (table != null && (table.activeOrderId == paid.id || table.activeOrderId == active.id)) {
        table
          ..status = TableStatus.available
          ..activeOrderId = null
          ..currentOrderAmount = 0.0
          ..runningMinutes = 0
          ..guestCount = 0
          ..assignedWaiter = null;
      }
    }
    _activeOrder = null;
    _selectedTable = null;
    notifyListeners();
    // Drawer totals and customer balances come from the server.
    unawaited(_refresh(['shift', 'customers', 'tables']));
    _printReceipt(paid);
    return PaymentResult.ok(paid);
  }

  /// Demo/test mode only (no server): books the payment the way the server
  /// would, so the screens and shift math can be exercised offline.
  void _settleLocally(RestaurantOrder o, String method,
      List<({String method, double amount})> legs, String? reference) {
    o
      ..status = OrderStatus.completed
      ..paidAt = DateTime.now()
      ..paymentMethod = PaymentMethodX.fromLabel(method).label
      ..paymentSplits = [
        for (final l in legs)
          PaymentLeg(method: PaymentMethodX.fromLabel(l.method).label, amount: roundMoney(l.amount)),
      ]
      ..paymentReference = (reference ?? '').trim().isEmpty ? null : reference!.trim();
    final shift = _currentShift;
    if (shift != null) {
      for (final leg in legs) {
        switch (PaymentMethodX.fromLabel(leg.method)) {
          case PaymentMethod.cash:
            shift.cashSales += leg.amount;
          case PaymentMethod.upi:
            shift.upiSales += leg.amount;
          case PaymentMethod.card:
            shift.cardSales += leg.amount;
          case PaymentMethod.credit:
            break;
        }
      }
    }
    if (!_orders.any((x) => x.id == o.id)) _orders.insert(0, o);
  }

  // Refunds
  /// Refunds a paid bill. Sent to the server first; returns null once the
  /// server recorded it (the order and drawer then show the server's
  /// numbers), otherwise why it was not recorded.
  Future<String?> processRefund({
    required String orderId,
    required double amount,
    required String reason,
    required bool isFullRefund,
    String refundMode = 'Cash',
    String? managerPin,
  }) async {
    final order = _orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) return 'Order not found';
    if (order.status != OrderStatus.completed) return 'Only paid bills can be refunded';
    // Cap by the bill (not cash tendered, which includes change) minus what
    // was already refunded.
    final refundable = order.grandTotal - order.refundedAmount;
    if (amount <= 0 || amount > refundable + 0.005) {
      return 'Refund must be between ₹1 and ${refundable.toStringAsFixed(2)}';
    }
    final error = await _push('order.refund', {
      'order_id': orderId,
      'amount_paise': toPaise(amount),
      'reason': reason,
      'is_full_refund': isFullRefund,
      'mode': refundModeToApi(refundMode),
      // FR-A3: refunds are manager-gated server-side.
      if (managerPin != null && managerPin.isNotEmpty) 'manager_pin': managerPin,
    });
    if (error == null) unawaited(_refresh(['shift', 'customers']));
    return error;
  }

  // Expenses
  final List<Expense> _expenses = [];
  List<Expense> get expenses => List.unmodifiable(_expenses);

  double get todayExpenses {
    final now = DateTime.now();
    return _expenses
        .where((e) => e.date.year == now.year && e.date.month == now.month && e.date.day == now.day)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get monthExpenses {
    final now = DateTime.now();
    return _expenses
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  void addExpense(Expense expense) {
    if (expense.amount <= 0) return;
    _expenses.insert(0, expense);
    if (expense.paymentMethod == 'Cash') {
      _currentShift?.expenses += expense.amount;
    }
    notifyListeners();
    _push('expense.create', {
      'local_id': expense.id,
      'title': expense.title,
      'category': expenseCategoryToApi(expense.category),
      'amount_paise': toPaise(expense.amount),
      'method': expense.paymentMethod,
      if (expense.vendor != null && expense.vendor!.isNotEmpty) 'vendor': expense.vendor,
      if (expense.reference != null && expense.reference!.isNotEmpty) 'reference': expense.reference,
      if (expense.description != null && expense.description!.isNotEmpty) 'note': expense.description,
    });
  }

  void deleteExpense(String id) {
    final expense = _expenses.where((e) => e.id == id).firstOrNull;
    if (expense == null) return;
    _expenses.remove(expense);
    // Reversal: a deleted cash expense no longer leaves the drawer.
    if (expense.paymentMethod == 'Cash' && _currentShift != null) {
      _currentShift!.expenses =
          (_currentShift!.expenses - expense.amount).clamp(0.0, double.infinity);
    }
    notifyListeners();
    _push('expense.delete', {'expense_id': id});
  }

  // Customers
  final List<Customer> _customers = [];
  List<Customer> get customers => List.unmodifiable(_customers);

  void addCustomer(Customer customer) {
    if (customer.phone.trim().isEmpty) return;
    _customers.insert(0, customer);
    notifyListeners();
    _push('customer.create', {
      'local_id': customer.id,
      'name': customer.name,
      'phone': customer.phone,
      if (customer.email != null && customer.email!.isNotEmpty) 'email': customer.email,
      if (customer.address != null && customer.address!.isNotEmpty) 'address': customer.address,
    });
  }

  /// FR-C1: book a credit sale (outstanding up) or settlement (outstanding
  /// down) against a customer's account.
  bool bookCustomerCredit({
    required String customerId,
    required String kind, // 'sale' | 'settlement'
    required double amount,
    required String reason,
  }) {
    final customer = _customers.where((c) => c.id == customerId).firstOrNull;
    if (customer == null || amount <= 0 || reason.trim().isEmpty) return false;
    if (kind == 'settlement') {
      if (amount > customer.outstandingCredit + 0.005) return false;
      customer.outstandingCredit =
          roundMoney((customer.outstandingCredit - amount).clamp(0.0, double.infinity));
    } else if (kind == 'sale') {
      customer.outstandingCredit = roundMoney(customer.outstandingCredit + amount);
    } else {
      return false;
    }
    notifyListeners();
    _push('credit.book', {
      'customer_id': customerId,
      'kind': kind,
      'amount_paise': toPaise(amount),
      'reason': reason,
    });
    return true;
  }

  // Inventory & Stock
  final List<InventoryItem> _inventory = [];
  List<InventoryItem> get inventory => List.unmodifiable(_inventory);

  List<InventoryItem> get lowStockItems =>
      List.unmodifiable(_inventory.where((i) => i.isLowStock));

  // Stock adjustment audit trail: who changed what, why, when.
  final List<StockAdjustment> _stockLog = [];
  List<StockAdjustment> get stockLog => List.unmodifiable(_stockLog);

  void adjustStock(String itemId, double change, String reason) {
    final item = _inventory.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;
    item.availableStock = (item.availableStock + change).clamp(0.0, double.infinity);
    _stockLog.insert(
      0,
      StockAdjustment(
        itemId: itemId,
        itemName: item.name,
        change: change,
        reason: reason,
        staffName: _currentStaff?.name ?? 'Staff',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
    _push('stock.adjust', {
      'item_id': itemId,
      'delta': change,
      'reason': reason,
    });
  }

  // Suppliers & Purchases
  final List<Supplier> _suppliers = [];
  List<Supplier> get suppliers => _suppliers;

  final List<PurchaseRecord> _purchases = [];
  List<PurchaseRecord> get purchases => _purchases;

  // Settings
  RestaurantSettings _settings = RestaurantSettings();
  RestaurantSettings get settings => _settings;

  /// Effective dining sections (Garden / AC Dining / Bar …): the settings
  /// list when configured, else the distinct floor names already on tables
  /// so older data/terminals keep working.
  List<String> get diningSections {
    final configured = _settings.sections
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (configured.isNotEmpty) return List.unmodifiable(configured);
    final floors = _tables
        .map((t) => t.floor.trim())
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return floors;
  }

  /// Server-computed dashboard KPIs (outlet-wide truth). Null when offline —
  /// screens fall back to locally computed numbers.
  DashboardStats? _serverDashboard;
  DashboardStats? get serverDashboard => _serverDashboard;

  /// On-demand server report for an arbitrary date range
  /// (GET /reports/dashboard?from=…&to=…, admin-only endpoint).
  DashboardStats? _rangeReport;
  DateTimeRange? _rangeReportKey;
  bool _rangeReportLoading = false;
  DashboardStats? get serverRangeReport => _rangeReport;
  DateTimeRange? get rangeReportKey => _rangeReportKey;
  bool get rangeReportLoading => _rangeReportLoading;

  /// Fetches outlet-wide stats for [range]. Cached by range key; no-op when
  /// offline, non-admin (endpoint is admin-gated) or already loading.
  Future<void> fetchRangeReport(DateTimeRange range) async {
    if (!apiEnabled || _api == null) return;
    if (_currentStaff?.role != StaffRole.admin) return;
    if (_rangeReportLoading) return;
    if (_rangeReportKey == range && _rangeReport != null) return;
    _rangeReportLoading = true;
    notifyListeners();
    try {
      // Date-only bounds: the server counts business days in the outlet's
      // time zone (inclusive of the end date).
      String ymd(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final q = {
        'outlet_id': _currentOutlet.id,
        'from': ymd(range.start),
        'to': ymd(range.end),
      };
      final rep = await _tryRead('/api/v1/reports/dashboard', q);
      if (rep is Map) {
        _rangeReport = dashboardReportFromApi(rep.cast<String, dynamic>());
        _rangeReportKey = range;
      }
    } finally {
      _rangeReportLoading = false;
      notifyListeners();
    }
  }

  /// Saves the outlet's legal/contact details (printed on bills) to the
  /// outlet record, and the display name to settings.
  void updateOutletProfile({
    required String name,
    required String address,
    required String phone,
    required String email,
    required String gstin,
    required String fssai,
  }) {
    if (!canManage) return;
    _currentOutlet = _currentOutlet.copyWith(
        address: address, phone: phone, email: email, gstin: gstin, fssai: fssai);
    final i = _outlets.indexWhere((o) => o.id == _currentOutlet.id);
    if (i >= 0) _outlets[i] = _currentOutlet;
    _settings = _withOutletProfile(_settings.copyWith(restaurantName: name));
    notifyListeners();
    _push('outlet.patch', {
      'address': address,
      'phone': phone,
      'email': email,
      'gstin': gstin,
      'fssai': fssai,
    });
    _push('settings.update', settingsToApi(_settings));
  }

  /// Saves outlet settings (managers only; the server refuses others, so a
  /// cashier's change is not even shown locally).
  void updateSettings(RestaurantSettings s) {
    if (apiEnabled && !canManage) return;
    _settings = s;
    notifyListeners();
    _push('settings.update', settingsToApi(s));
  }

  bool get canManage =>
      _currentStaff?.role == StaffRole.manager || _currentStaff?.role == StaffRole.admin;

  /// Waiters take orders; collecting money is cashier+ on the server.
  bool get canTakePayment =>
      _currentStaff != null && _currentStaff!.role != StaffRole.waiter && _currentStaff!.role != StaffRole.kitchen;

  // ---- Edit / delete (saved on the server first) ----
  // Each returns null once the server saved the change (the lists then show
  // the server's copy), otherwise why it was not saved.

  /// Voids an order nobody has paid for (wrong table, customer left). After
  /// a KOT reached the kitchen a manager PIN is needed unless the signed-in
  /// staff is a manager.
  Future<String?> cancelOrder(String orderId, {String reason = '', String? managerPin}) async {
    final error = await _push('order.cancel', {
      'order_id': orderId,
      if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      if (managerPin != null && managerPin.isNotEmpty) 'manager_pin': managerPin,
    });
    if (error == null && (_activeOrder?.id == orderId || _activeOrder?.id == _sync?.resolveId(orderId))) {
      _activeOrder = null;
      _selectedTable = null;
      notifyListeners();
    }
    return error;
  }

  Future<String?> updateCustomer(String id,
          {required String name, required String phone, String email = '', String address = ''}) =>
      _push('customer.patch', {
        'customer_id': id,
        'name': name.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'address': address.trim(),
      });

  Future<String?> deleteCustomer(String id) => _push('customer.delete', {'customer_id': id});

  Future<String?> updateSupplier(String id,
          {required String name, required String mobile, String email = '', String category = ''}) =>
      _push('supplier.patch', {
        'supplier_id': id,
        'name': name.trim(),
        'mobile': mobile.trim(),
        'email': email.trim(),
        'category': category.trim(),
      });

  Future<String?> deleteSupplier(String id) => _push('supplier.delete', {'supplier_id': id});

  /// Edits an item's details; stock only moves through [adjustStock] so
  /// every change is in the stock log.
  Future<String?> updateInventoryItem(String id,
          {required String name,
          required String unit,
          required double minStock,
          required double costPerUnit,
          String batchNo = '',
          String rackNo = ''}) =>
      _push('inventory.patch', {
        'inventory_item_id': id,
        'name': name.trim(),
        'unit': unit.trim(),
        'min_stock': minStock,
        'cost_paise': toPaise(costPerUnit),
        'batch_no': batchNo.trim(),
        'rack_no': rackNo.trim(),
      });

  Future<String?> deleteInventoryItem(String id) =>
      _push('inventory.delete', {'inventory_item_id': id});

  /// Edits an expense. The payment method can't change (delete and re-add).
  Future<String?> updateExpense(String id,
          {required String title,
          required ExpenseCategory category,
          required double amount,
          String vendor = '',
          String reference = '',
          String note = ''}) =>
      _push('expense.patch', {
        'expense_id': id,
        'title': title.trim(),
        'category': expenseCategoryToApi(category),
        'amount_paise': toPaise(amount),
        'vendor': vendor.trim(),
        'reference': reference.trim(),
        'note': note.trim(),
      });

  // ---- Back-office actions (W2/W3/W4/W5/W11) ----

  void addMenuItem(MenuItem item) {
    final scopedItem = item.outletId == null
        ? item.copyWith(outletId: _currentOutlet.id)
        : item;
    _menuItems.add(scopedItem);
    _rebuildCategories();
    notifyListeners();
    _push('menu.create', {
      'local_id': scopedItem.id,
      'outlet_id': scopedItem.outletId ?? _currentOutlet.id,
      'category_id': scopedItem.category,
      'name': scopedItem.name,
      if (scopedItem.description.isNotEmpty) 'description': scopedItem.description,
      'price_paise': toPaise(scopedItem.price),
      'is_veg': scopedItem.isVeg,
      'image_url': scopedItem.imageUrl,
      'is_bestseller': scopedItem.isBestseller,
      if (scopedItem.variants.isNotEmpty) 'variants': menuVariantsToApi(scopedItem.variants),
      if (scopedItem.modifierGroups.isNotEmpty)
        'modifier_groups': menuModifierGroupsToApi(scopedItem.modifierGroups),
    });
  }

  void updateMenuItem(
    MenuItem item, {
    bool? isAvailable,
    List<ProductVariant>? variants,
    List<ModifierGroup>? modifierGroups,
  }) {
    final idx = _menuItems.indexWhere((m) => m.id == item.id);
    if (idx == -1) return;
    final next = (isAvailable == null && variants == null && modifierGroups == null)
        ? item
        : item.copyWith(isAvailable: isAvailable, variants: variants, modifierGroups: modifierGroups);
    _menuItems[idx] = next;
    notifyListeners();
    _push('menu.update', {
      'menu_item_id': item.id,
      'category_id': item.category,
      'name': item.name,
      'description': item.description, // '' clears it
      'price_paise': toPaise(item.price),
      'is_veg': item.isVeg,
      'image_url': item.imageUrl,
      'is_bestseller': item.isBestseller,
      'is_available': ?isAvailable,
      if (variants != null) 'variants': menuVariantsToApi(variants),
      if (modifierGroups != null)
        'modifier_groups': menuModifierGroupsToApi(modifierGroups),
    });
  }

  /// Base URL of the configured backend ('' when running offline/demo).
  String get apiBaseUrl => _api?.baseUrl ?? '';

  /// Uploads a menu photo to the server and returns its `/media/…` URL.
  /// Throws ApiException/NetworkException — callers surface a message.
  Future<String> uploadMenuImage(
    List<int> bytes, {
    required String filename,
    required String contentType,
  }) async {
    return _uploadImage(bytes, filename: filename, contentType: contentType);
  }

  // ---- My profile (self-service; online only) ----

  /// Saves the signed-in staff member's own name / mobile / photo. Returns
  /// an error message, or null on success.
  Future<String?> updateMyProfile({String? name, String? mobile, String? avatarUrl}) async {
    final me = _currentStaff;
    if (me == null) return 'Not signed in';
    if (!apiEnabled || _api == null) return 'Profile changes need the server';
    try {
      final resp = await _api!.request('PATCH', '/api/v1/me', body: {
        'name': ?name,
        'mobile': ?mobile,
        'avatar_url': ?avatarUrl,
      });
      if (resp is Map) {
        final updated = staffFromApi(resp.cast<String, dynamic>());
        final merged = Staff(
          id: me.id,
          outletId: me.outletId,
          name: updated.name,
          role: me.role,
          pin: me.pin,
          avatarUrl: updated.avatarUrl,
          mobile: updated.mobile,
          isActive: me.isActive,
          isProtected: me.isProtected,
        );
        _currentStaff = merged;
        final i = _staffList.indexWhere((s) => s.id == me.id);
        if (i >= 0) _staffList[i] = merged;
        unawaited(_saveLoginSnapshot());
        notifyListeners();
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } on NetworkException {
      return 'You are offline. Connect to the internet to update your profile.';
    }
  }

  /// Changes the signed-in staff member's own PIN. Returns an error message,
  /// or null on success. The offline PIN cache is updated so the new PIN also
  /// works without network.
  Future<String?> changeMyPin(String currentPin, String newPin) async {
    final me = _currentStaff;
    if (me == null) return 'Not signed in';
    if (!apiEnabled || _api == null) return 'PIN changes need the server';
    try {
      await _api!.request('POST', '/api/v1/me/pin',
          body: {'current_pin': currentPin, 'new_pin': newPin});
      return null;
    } on ApiException catch (e) {
      return e.code == 'pin_locked' ? 'Too many wrong attempts. Try again in 15 minutes.' : e.message;
    } on NetworkException {
      return 'You are offline. Connect to the internet to change your PIN.';
    }
  }

  /// Uploads a profile photo; returns its /media URL.
  Future<String> uploadMyAvatar(List<int> bytes, {required String filename, required String contentType}) =>
      _uploadImage(bytes, filename: filename, contentType: contentType, path: '/api/v1/me/avatar');

  /// Uploads a generic settings image (e.g. a custom UPI QR override).
  Future<String> uploadSettingsImage(
    List<int> bytes, {
    required String filename,
    required String contentType,
  }) async {
    return _uploadImage(bytes, filename: filename, contentType: contentType,
        path: '/api/v1/uploads/image');
  }

  Future<String> _uploadImage(
    List<int> bytes, {
    required String filename,
    required String contentType,
    String path = '/api/v1/uploads/menu-image',
  }) async {
    if (!apiEnabled || _api == null) {
      throw NetworkException('Upload requires the server connection');
    }
    final data = await _api!.uploadImage(
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      query: {'outlet_id': _currentOutlet.id},
      path: path,
    );
    return (data['image_url'] as String?) ?? '';
  }

  void deleteMenuItem(String id) {
    _menuItems.removeWhere((m) => m.id == id);
    _rebuildCategories();
    notifyListeners();
    _push('menu.delete', {'menu_item_id': id});
  }

  void addStaff(Staff staff) {
    final assignedOutlet = staff.role == StaffRole.waiter || staff.role == StaffRole.kitchen
        ? (staff.outletId ?? _currentOutlet.id)
        : staff.outletId;
    final s = Staff(
      id: staff.id,
      outletId: assignedOutlet,
      name: staff.name,
      role: staff.role,
      pin: staff.pin,
      avatarUrl: staff.avatarUrl,
      mobile: staff.mobile,
      isActive: staff.isActive,
      isProtected: false,
    );
    _staffList.add(s);
    notifyListeners();
    _push('staff.create', {
      'local_id': s.id,
      'name': s.name,
      'role': s.role.name,
      'pin': s.pin,
      if (s.outletId != null) 'staff_outlet_id': s.outletId,
      if (s.avatarUrl.isNotEmpty) 'avatar_url': s.avatarUrl,
      if (s.mobile.isNotEmpty) 'mobile': s.mobile,
    });
  }

  bool updateStaff(String id, {String? name, StaffRole? role, String? outletId, bool? isActive, String? pin, String? mobile}) {
    final idx = _staffList.indexWhere((s) => s.id == id);
    if (idx == -1) return false;
    final s = _staffList[idx];
    // Owner (main admin) protection: only itself may edit itself, and even
    // itself cannot deactivate/demote. Any other actor is blocked entirely.
    if (s.isProtected) {
      if (_currentStaff?.id != s.id) return false;
      if (isActive == false) return false;
      if (role != null && role != StaffRole.admin) return false;
    } else {
      // Managers cannot edit any admin row.
      if (s.role == StaffRole.admin && _currentStaff?.role == StaffRole.manager) {
        return false;
      }
      // No self-deactivation, no self-demotion.
      if (_currentStaff?.id == s.id) {
        if (isActive == false) return false;
        if (role != null && role != s.role) return false;
      }
    }
    final effectiveRole = role ?? s.role;
    // outletId == '' means "unassign / org-wide floater" for non
    // waiter/kitchen roles (backend clears on empty string).
    final outletCleared = outletId != null && outletId.isEmpty;
    final effectiveOutlet = outletCleared
        ? null
        : (effectiveRole == StaffRole.waiter || effectiveRole == StaffRole.kitchen
            ? (outletId ?? s.outletId ?? _currentOutlet.id)
            : (outletId ?? s.outletId));
    _staffList[idx] = Staff(
      id: s.id,
      outletId: effectiveOutlet,
      name: (name != null && name.trim().isNotEmpty) ? name.trim() : s.name,
      role: effectiveRole,
      pin: (pin != null && pin.isNotEmpty) ? pin : s.pin,
      avatarUrl: s.avatarUrl,
      mobile: (mobile != null) ? mobile.trim() : s.mobile,
      isActive: isActive ?? s.isActive,
      isProtected: s.isProtected,
    );
    notifyListeners();
    _push('staff.patch', {
      'staff_id': id,
      'name': ?name,
      if (role != null) 'role': role.name,
      // Send '' to clear outlet (backend treats '' as NULL); omit when unchanged.
      if (outletCleared) 'staff_outlet_id': '',
      if (!outletCleared) 'staff_outlet_id': ?effectiveOutlet,
      'is_active': ?isActive,
      'pin': ?((pin != null && pin.isNotEmpty) ? pin : null),
      'mobile': ?mobile,
    });
    return true;
  }

  void addInventoryItem(InventoryItem item) {
    _inventory.add(item);
    notifyListeners();
    _push('inventory.create', {
      'local_id': item.id,
      'name': item.name,
      'unit': item.unit,
      'stock': item.availableStock,
      'min_stock': item.minStock,
      'cost_paise': toPaise(item.costPerUnit),
      // Purchase provenance — server op ignores unknown keys for now; the
      // ledger keeps them locally for the stock log & item card.
      if (item.batchNo != null && item.batchNo!.isNotEmpty) 'batch_no': item.batchNo,
      if (item.rackNo != null && item.rackNo!.isNotEmpty) 'rack_no': item.rackNo,
      if (item.purchasedAt != null)
        'purchased_at': item.purchasedAt!.toUtc().toIso8601String(),
    });
  }

  void addSupplier(Supplier supplier) {
    _suppliers.add(supplier);
    notifyListeners();
    _push('supplier.create', {
      'local_id': supplier.id,
      'name': supplier.name,
      'mobile': supplier.mobile,
      if (supplier.email != null && supplier.email!.isNotEmpty) 'email': supplier.email,
      if (supplier.category.isNotEmpty) 'category': supplier.category,
    });
  }

  // ---- Supplier payment ledger (W5): pay dues, track history by date ----
  // Server truth: POST /suppliers/{id}/payments reduces the due atomically;
  // GET /suppliers/{id}/payments hydrates the ledger for the outlet.

  final List<SupplierPayment> _supplierPayments = [];
  List<SupplierPayment> get supplierPayments => List.unmodifiable(_supplierPayments);

  List<SupplierPayment> supplierPaymentsFor(String supplierId) =>
      List.unmodifiable(
          _supplierPayments.where((p) => p.supplierId == supplierId));

  /// Hydrates the payment ledger from the server for one supplier (merged by
  /// id; local optimistic rows survive until the server knows them).
  Future<void> fetchSupplierPayments(String supplierId) async {
    if (!apiEnabled || _api == null || !_sync!.online) return;
    final localId = _serverIdFor(supplierId);
    final id = localId ?? supplierId;
    if (id.isEmpty) return;
    try {
      final data = await _api!.request(
          'GET', '/api/v1/suppliers/$id/payments',
          query: {'outlet_id': _currentOutlet.id});
      if (data is! Map || data['payments'] is! List) return;
      final server = (data['payments'] as List)
          .whereType<Map>()
          .map((j) => supplierPaymentFromApi(j.cast<String, dynamic>()))
          .toList();
      // Replace this supplier's rows with server truth, keep others.
      _supplierPayments
        ..removeWhere((p) => p.supplierId == supplierId)
        ..insertAll(0, server);
      notifyListeners();
    } on NetworkException {
      // offline — keep the local ledger
    } on ApiException {
      // per-supplier read failures are non-fatal
    }
  }

  /// Records a payment against [supplierId]'s outstanding due and reduces it.
  /// Returns false when the payment exceeds the outstanding amount.
  bool paySupplier({
    required String supplierId,
    required double amount,
    required String method,
    DateTime? at,
    String? reference,
  }) {
    final sup = _suppliers.where((s) => s.id == supplierId).firstOrNull;
    if (sup == null || amount <= 0) return false;
    if (amount > sup.outstanding + 0.005) return false;
    final when = at ?? DateTime.now();
    final pay = SupplierPayment(
      id: 'pay-${DateTime.now().millisecondsSinceEpoch}',
      supplierId: supplierId,
      supplierName: sup.name,
      amount: amount,
      method: method,
      paidAt: when,
      reference: reference,
      staffName: _currentStaff?.name ?? 'Staff',
    );
    sup.outstanding = (sup.outstanding - amount).clamp(0.0, double.infinity);
    _supplierPayments.insert(0, pay);
    notifyListeners();
    // A direct cash payout leaves the physical drawer (mirrors the server,
    // which books cash payouts through the expense flow into shift math).
    if (method == 'Cash' && _currentShift != null) {
      _currentShift!.expenses += amount;
    }
    _push('supplier.payment', {
      'local_id': pay.id,
      'supplier_id': supplierId,
      'amount_paise': toPaise(amount),
      'method': supplierMethodToApi(method),
      'at': when.toUtc().toIso8601String(),
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    });
    return true;
  }

  void createPurchase({
    required String invoiceNo,
    String? supplierId,
    required String status,
    required double totalAmount,
    required List<Map<String, dynamic>> lines,
    DateTime? purchasedAt,
  }) {
    final record = PurchaseRecord(
      id: 'pur-${DateTime.now().millisecondsSinceEpoch}',
      invoiceNumber: invoiceNo,
      supplierName: _suppliers.where((s) => s.id == supplierId).firstOrNull?.name ?? '',
      date: purchasedAt ?? DateTime.now(),
      totalAmount: totalAmount,
      paymentStatus: status == 'pending' ? 'Pending' : 'Paid',
      itemsSummary: lines.map((l) => '${l['name']} ×${l['qty']}').join(', '),
    );
    _purchases.insert(0, record);
    // Mirror the server's stock intake locally (ops.go bumps inventory_items
    // on purchase create) so the terminal's ingredient list moves immediately.
    // No stock.adjust push — that would double-count the intake.
    for (final line in lines) {
      final itemId = line['inventory_item_id'] as String?;
      final qty = (line['qty'] as num?)?.toDouble() ?? 0;
      if (itemId == null || itemId.isEmpty || qty <= 0) continue;
      final item = _inventory.where((i) => i.id == itemId).firstOrNull;
      if (item == null) continue;
      item.availableStock = (item.availableStock + qty).clamp(0.0, double.infinity);
    }
    // Credit purchases increase the supplier's outstanding due; the existing
    // markPurchasePaid settle clears it (mirrors server truth).
    if (status == 'pending' && supplierId != null && supplierId.isNotEmpty) {
      final sup = _suppliers.where((s) => s.id == supplierId).firstOrNull;
      if (sup != null) {
        sup.outstanding += totalAmount;
        sup.lastPurchase = record.date;
      }
    }
    notifyListeners();
    _push('purchase.create', {
      'local_id': record.id,
      'invoice_no': invoiceNo,
      if (supplierId != null && supplierId.isNotEmpty) 'supplier_id': supplierId,
      'status': status,
      'total_paise': toPaise(totalAmount),
      'purchased_at': record.date.toUtc().toIso8601String(),
      'items': lines,
    });
  }

  void markPurchasePaid(String id) {
    final idx = _purchases.indexWhere((p) => p.id == id);
    if (idx == -1 || _purchases[idx].paymentStatus == 'Paid') return;
    final p = _purchases[idx];
    _purchases[idx] = PurchaseRecord(
      id: p.id,
      invoiceNumber: p.invoiceNumber,
      supplierName: p.supplierName,
      date: p.date,
      totalAmount: p.totalAmount,
      paymentStatus: 'Paid',
      itemsSummary: p.itemsSummary,
    );
    notifyListeners();
    _push('purchase.patch', {'purchase_id': id, 'status': 'paid'});
  }

  /// Moves an existing table to another dining section (its floor name).
  /// True while the table has a running order or bill; such a table can't be
  /// edited away, deleted, or have its status overridden by hand.
  bool tableIsBusy(RestaurantTable t) =>
      t.activeOrderId != null ||
      t.status == TableStatus.occupied ||
      t.status == TableStatus.billing ||
      t.mergedWithTableId != null;

  /// Renames / resizes / re-sections a table (managers). Returns an error
  /// message, or null on success.
  String? editTable(String tableId, {required String tableNumber, required int seats, required String section}) {
    if (!canManage) return 'Only managers can edit tables';
    final table = _tables.where((t) => t.id == tableId).firstOrNull;
    if (table == null) return 'Table not found';
    final number = tableNumber.trim();
    final name = section.trim();
    if (number.isEmpty || number.length > 20) return 'Enter a table number (up to 20 characters)';
    if (seats < 1 || seats > 50) return 'Seats must be between 1 and 50';
    if (name.isEmpty) return 'Choose a section';
    if (_tables.any((t) => t.id != tableId && t.tableNumber.toLowerCase() == number.toLowerCase())) {
      return 'Table $number already exists';
    }
    final changes = <String, dynamic>{
      if (number != table.tableNumber) 'table_number': number,
      if (seats != table.seats) 'seats': seats,
      if (name != table.floor) 'floor': name,
    };
    if (changes.isEmpty) return null;
    table
      ..tableNumber = number
      ..seats = seats
      ..floor = name;
    notifyListeners();
    _push('table.patch', {'table_id': table.id, ...changes});
    return null;
  }

  /// Removes a free table from the floor plan (managers). Returns an error
  /// message, or null on success. Past bills keep their table reference.
  String? deleteTable(String tableId) {
    if (!canManage) return 'Only managers can delete tables';
    final table = _tables.where((t) => t.id == tableId).firstOrNull;
    if (table == null) return 'Table not found';
    if (tableIsBusy(table)) return 'Table ${table.tableNumber} has a running order. Close or move it first.';
    _tables.removeWhere((t) => t.id == tableId);
    if (_selectedTable?.id == tableId) _selectedTable = null;
    notifyListeners();
    _push('table.delete', {'table_id': tableId});
    return null;
  }

  /// Marks a free table reserved / cleaning / available. Running tables keep
  /// their order-driven status.
  String? changeTableStatus(String tableId, TableStatus status) {
    final table = _tables.where((t) => t.id == tableId).firstOrNull;
    if (table == null) return 'Table not found';
    if (status == TableStatus.occupied || status == TableStatus.billing) {
      return "Occupied and billing follow the table's order";
    }
    if (tableIsBusy(table)) return 'Table ${table.tableNumber} has a running order';
    if (table.status == status) return null;
    table.status = status;
    notifyListeners();
    _push('table.status', {'table_id': table.id, 'status': tableStatusToApi(status)});
    return null;
  }

  void updateTableSection(String tableId, String section) {
    final name = section.trim();
    final table = _tables.where((t) => t.id == tableId).firstOrNull;
    if (table == null || name.isEmpty || table.floor == name) return;
    table.floor = name;
    notifyListeners();
    _push('table.patch', {'table_id': table.id, 'floor': name});
  }

  void addTable({required String tableNumber, required int seats, required String floor}) {
    final table = RestaurantTable(
      id: 't-${DateTime.now().millisecondsSinceEpoch}',
      tableNumber: tableNumber,
      seats: seats,
      floor: floor,
      status: TableStatus.available,
    );
    _tables.add(table);
    notifyListeners();
    _push('table.create', {
      'local_id': table.id,
      'outlet_id': _currentOutlet.id,
      'table_number': tableNumber,
      'seats': seats,
      'floor': floor,
      'status': 'available',
    });
  }

  // ---- Server-side log reads (W6/W7/W8): direct reads, not outbox ops ----

  String? _serverIdFor(String? localId) =>
      (localId == null || localId.isEmpty) ? null : (_sync?.idMap[localId] ?? localId);

  /// FR-C1: credit audit trail for one customer (server truth).
  Future<List<Map<String, dynamic>>> fetchCreditLog(String customerId) async {
    if (!apiEnabled || _api == null || !_sync!.online) return const [];
    final id = _serverIdFor(customerId);
    try {
      final data = await _api!.request(
        'GET', '/api/v1/customers/$id/credit-log',
        query: {'outlet_id': _currentOutlet.id},
      );
      if (data is Map && data['entries'] is List) {
        return (data['entries'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    } on ApiException catch (e) {
      _lastSyncError = e.message;
    } on NetworkException catch (_) {
      // Offline: the log simply isn't available right now.
    }
    return const [];
  }

  /// FR-I1: server-side stock adjustment audit log.
  Future<List<Map<String, dynamic>>> fetchStockAdjustments() async {
    if (!apiEnabled || _api == null || !_sync!.online) return const [];
    try {
      final data = await _api!.request(
        'GET', '/api/v1/inventory/adjustments',
        query: {'outlet_id': _currentOutlet.id},
      );
      if (data is Map && data['adjustments'] is List) {
        return (data['adjustments'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    } on ApiException catch (e) {
      _lastSyncError = e.message;
    } on NetworkException catch (_) {
      // Offline: the log simply isn't available right now.
    }
    return const [];
  }

  /// FR-R3: Z-report straight from the server for a closed shift
  /// (local shift id is translated through the sync id map).
  Future<Map<String, dynamic>?> fetchZReport(String localShiftId) async {
    if (!apiEnabled || _api == null || !_sync!.online) return null;
    final id = _serverIdFor(localShiftId);
    if (id == null) return null;
    try {
      final data = await _api!.request('GET', '/api/v1/reports/shift/$id/zreport',
          query: {'outlet_id': _currentOutlet.id});
      return data is Map ? data.cast<String, dynamic>() : null;
    } on ApiException catch (_) {
      return null;
    } on NetworkException catch (_) {
      return null;
    }
  }

  /// Prints the Z-report on the billing printer. False with [printerError]
  /// set when no printer is configured or printing fails.
  Future<bool> printZReport(Shift shift, {Map<String, dynamic>? server}) async {
    try {
      await _effectivePrinter.send(buildZReportBytes(shift, _settings, server: server));
      _printerError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _printerError = friendlyPrintError(_effectivePrinter.name, e);
      notifyListeners();
      return false;
    }
  }

  void _switchOutlet(Outlet outlet) {
    // Single-outlet binding (waiters + kitchen): staff assigned to one outlet
    // cannot operate another. Switching is hidden at the UI layer and rejected
    // here as a backstop.
    if (_currentStaff != null && !_currentStaff!.canAccessOutlet(outlet.id)) {
      return;
    }
    _currentOutlet = outlet;
    _rebuildCategories();
    // The saved login follows the counter: a restart must land back here.
    unawaited(_saveLoginSnapshot());
    // Strict outlet isolation: drop the previous outlet's board immediately so
    // no stale cross-outlet ticket is ever visible, then rehydrate.
    _kots.clear();
    unawaited(_realtime?.disconnect());
    notifyListeners();
    // A signed-in session is bound to the previous outlet server-side; the UI
    // signs the staff member out and back in, which hydrates the new outlet.
    if (apiEnabled && _currentStaff == null) {
      unawaited(hydratePublic());
    }
  }

  // Connection state. The app is online-only: while the server can't be
  // reached nothing can be saved, and the shell shows a "No connection"
  // screen instead of letting staff work on data that would be lost.
  bool get isOfflineMode => apiEnabled && !(_sync?.online ?? false);

  /// Writes sent and not answered yet.
  int get pendingSyncCount => _sync?.pending ?? 0;
  bool get realtimeConnected => _realtime?.connected ?? false;

  /// Checks the server and re-reads the outlet. Returns true when the server
  /// answered.
  Future<bool> triggerSync() async {
    if (!apiEnabled || _sync == null) return false;
    final ok = await _sync!.probe();
    if (ok) {
      if (_currentStaff == null && _pendingRestore) {
        await _runPendingRestore();
      } else {
        _hydrating = false;
        await hydrateOutlet();
      }
    }
    notifyListeners();
    return ok;
  }

  // ---- Printing (P5.1: ESC/POS hooks) ----

  PrinterAdapter get _effectivePrinter =>
      _printer ?? printerFromSetting(_settings.billingPrinter);

  /// The resolved printer for the current settings (None when unconfigured) —
  /// surfaced on the dashboard + printer status screen.
  PrinterAdapter? get printer {
    final p = _effectivePrinter;
    return p is NullPrinter ? null : p;
  }

  /// Sends a small test page so staff can verify the printer connection.
  Future<bool> printTestPage() async {
    try {
      await _effectivePrinter.send(buildTestPageBytes());
      _printerError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _printerError = friendlyPrintError(_effectivePrinter.name, e);
      notifyListeners();
      return false;
    }
  }

  /// Auto-prints the bill at payment. Silent when no printer is set up (a
  /// terminal without a printer is a valid setup); real failures surface.
  void _printReceipt(RestaurantOrder order) {
    if (!apiEnabled || _effectivePrinter is NullPrinter) return;
    _sendPrint(buildReceiptBytes(order, _settings), _effectivePrinter);
  }

  /// Reprints a (completed) bill on the configured printer. Returns false with
  /// [printerError] set when printing fails; honors settings.allowReprint.
  Future<bool> reprintReceipt(RestaurantOrder order) async {
    if (!_settings.allowReprint) {
      _printerError = 'Reprint is disabled in Settings';
      notifyListeners();
      return false;
    }
    try {
      await _effectivePrinter.send(buildReceiptBytes(order, _settings));
      _printerError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _printerError = friendlyPrintError(_effectivePrinter.name, e);
      notifyListeners();
      return false;
    }
  }

  PrinterAdapter get _kitchenPrinter => printerFromSetting(
      _settings.kitchenPrinter.trim().isNotEmpty
          ? _settings.kitchenPrinter
          : _settings.billingPrinter);

  /// Why the most recent KOT did not print (null when it printed or is still
  /// sending). Unlike bills, auto-print KOT is on by default, so a missing
  /// printer is a misconfiguration the kitchen would otherwise never notice.
  String? _kotPrintError;
  String? get kotPrintError => _kotPrintError;

  void _printKot(KitchenOrderTicket kot) {
    _kotPrintError = null;
    if (!apiEnabled || !_settings.autoPrintKOT) return;
    unawaited(reprintKot(kot));
  }

  /// Sends a KOT to the kitchen printer (billing printer as fallback).
  /// Returns false with [kotPrintError] set when it did not print.
  Future<bool> reprintKot(KitchenOrderTicket kot) async {
    final printer = _kitchenPrinter;
    try {
      await printer.send(buildKotBytes(kot, _settings));
      _kotPrintError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _kotPrintError = e is PrinterNotConfigured
          ? 'KOT not printed: no kitchen printer set. Add one in Settings → Printers.'
          : friendlyPrintError(printer.name, e);
      notifyListeners();
      return false;
    }
  }

  void _sendPrint(List<int> bytes, PrinterAdapter adapter) {
    unawaited(() async {
      try {
        await adapter.send(bytes);
        _printerError = null;
      } catch (e) {
        _printerError = friendlyPrintError(adapter.name, e);
      }
      notifyListeners();
    }());
  }
}

/// Outcome of [PosProvider.completePayment]: the paid order, or why the
/// payment was not saved.
class PaymentResult {
  final RestaurantOrder? order;
  final String? error;
  const PaymentResult.ok(RestaurantOrder this.order) : error = null;
  const PaymentResult.failed(String this.error) : order = null;
  bool get ok => order != null;
}

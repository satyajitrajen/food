import 'dart:async';

import 'package:flutter/material.dart';
import '../core/api/api_client.dart';
import '../core/api/dto.dart';
import '../core/auth/pin_vault.dart';
import '../core/auth/tenant.dart';
import '../core/printing/printing.dart';
import '../core/printing/receipt_builder.dart';
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

/// API base URL; override with --dart-define=FOODPOS_API_URL=...
const String kDefaultApiBaseUrl =
    String.fromEnvironment('FOODPOS_API_URL', defaultValue: 'https://food.nexorytechnologies.com');

class PosProvider extends ChangeNotifier {
  /// When true the provider talks to the Go backend (API writes with an
  /// offline outbox, SSE realtime, cache-first reads). False = demo mode.
  final bool apiEnabled;
  ApiClient? _api;
  SyncEngine? _sync;
  RealtimeChannel? _realtime;
  PrinterAdapter? _printer;
  PinVault? _pinVault;
  TenantStore? _tenantStore;
  TenantInfo? _tenant;
  EntitlementSnapshot? _entitlement;
  bool _hydrating = false;
  String? _lastSyncError;
  DateTime? _lastSyncAt;
  String? _printerError;

  String? get lastSyncError => _lastSyncError;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get printerError => _printerError;

  PosProvider({this.apiEnabled = false, PrinterAdapter? printer}) {
    _printer = printer;
    if (apiEnabled) {
      _api = ApiClient(baseUrl: kDefaultApiBaseUrl, onSessionChanged: _persistSession);
      _pinVault = PinVault();
      _tenantStore = TenantStore();
      _sync = SyncEngine(
        api: _api!,
        store: OutboxStore(),
        onChanged: (_, _) => notifyListeners(),
        onAck: applyServerTruth,
        onError: (message) {
          _lastSyncError = message;
          notifyListeners();
        },
      );
      _registerOps();
      unawaited(_bootstrap());
    }
    _seedData();
  }

  void _persistSession(AuthSession? session) {
    unawaited(OutboxStore().saveSession(session?.accessToken, session?.refreshToken));
  }

  Future<void> _bootstrap() async {
    // Restore the bound tenant + last entitlement before any network calls so
    // hydrations are org-scoped and offline grace survives restarts.
    if (_tenantStore != null) {
      _tenant = await _tenantStore!.load();
      _entitlement = await _tenantStore!.loadEntitlement();
    }
    await _sync!.initialize();
    await _sync!.probe();
    if (_sync!.online && _tenant != null) {
      await hydratePublic();
    }
    if (_currentStaff != null) {
      unawaited(_postLoginSync());
    }
  }

  Future<void> _postLoginSync() async {
    if (!apiEnabled) return;
    await _sync!.probe();
    if (_sync!.online) {
      await hydrateOutlet();
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
      case 'shift.updated':
        _applyServerShift(payload);
        break;
      default:
        break;
    }
    notifyListeners();
  }

  MenuItem? _menuLookup(String id) =>
      _menuItems.where((m) => m.id == id).firstOrNull;

  /// Re-binds this terminal to a different org (change-code flow): clears the
  /// previous tenant + entitlement, then bootstraps the new code.
  Future<void> rebindOrg(String code) async {
    _tenant = null;
    _entitlement = null;
    _staffList.clear();
    _outlets.clear();
    await _tenantStore?.clear();
    await _tenantStore?.clearEntitlement();
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
    final idx = _kots.indexWhere((k) => k.id == incoming.id);
    final prevStatus = idx >= 0 ? _kots[idx].status : null;
    if (idx >= 0) {
      _kots[idx] = incoming;
    } else {
      _kots.insert(0, incoming);
    }
    _maybeFireReadyAlert(previous: prevStatus, kot: incoming);
  }

  void _upsertServerTable(Map<String, dynamic> j) {
    final incoming = tableFromApi(j);
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

  void _upsertServerInventoryItem(Map<String, dynamic> j) {
    final incoming = inventoryItemFromApi(j);
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
        if (data != null) _upsertServerInventoryItem(data);
        break;
      case 'supplier.create':
        if (data != null) _upsertServerSupplier(data, replaceLocalId: payload['local_id']?.toString());
        break;
      case 'purchase.create':
      case 'purchase.patch':
        if (data != null) _upsertServerPurchase(data, replaceLocalId: payload['local_id']?.toString());
        break;
      case 'table.create':
        if (data != null) _upsertServerTable(data);
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
      }
      final staff = await _api!.request('GET', '/api/v1/staff',
          auth: false, query: orgQuery);
      if (staff is Map && staff['staff'] is List) {
        _staffList
          ..clear()
          ..addAll((staff['staff'] as List)
              .whereType<Map>()
              .map((s) => staffFromApi(s.cast<String, dynamic>()))
              .where((s) => s.isActive));
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

  Future<void> hydrateOutlet() async {
    if (!apiEnabled || _api == null || _hydrating) return;
    _hydrating = true;
    final outletId = _currentOutlet.id;
    Map<String, String> q = {'outlet_id': outletId};
    try {
      final menu = await _tryRead('/api/v1/menu', q);
      if (menu is Map && menu['menu_items'] is List) {
        _menuItems
          ..clear()
          ..addAll((menu['menu_items'] as List)
              .whereType<Map>()
              .map((m) => menuItemFromApi(m.cast<String, dynamic>())));
        _rebuildCategories();
      }
      final tables = await _tryRead('/api/v1/tables', q);
      if (tables is Map && tables['tables'] is List) {
        _tables
          ..clear()
          ..addAll((tables['tables'] as List)
              .whereType<Map>()
              .map((t) => tableFromApi(t.cast<String, dynamic>())));
      }
      final orders = await _tryRead(
          '/api/v1/orders', {'outlet_id': outletId, 'limit': '100'});
      if (orders is Map && orders['orders'] is List) {
        _orders
          ..clear()
          ..addAll((orders['orders'] as List)
              .whereType<Map>()
              .map((o) => orderFromApi(o.cast<String, dynamic>(), _menuLookup)));
      }
      final kots = await _tryRead('/api/v1/kots', q);
      if (kots is Map && kots['kots'] is List) {
        _kots
          ..clear()
          ..addAll((kots['kots'] as List)
              .whereType<Map>()
              .map((k) => kotFromApi(k.cast<String, dynamic>())));
      }
      final settings = await _tryRead('/api/v1/settings', q);
      if (settings is Map) {
        _settings = settingsFromApi(settings.cast<String, dynamic>());
      }
      final shift = await _tryRead('/api/v1/shifts/current', q);
      if (shift is Map && shift['shift'] is Map) {
        _currentShift = shiftFromApi((shift['shift'] as Map).cast<String, dynamic>());
      } else if (shift is Map) {
        _currentShift = null;
      }
      final expenses = await _tryRead('/api/v1/expenses', q);
      if (expenses is Map && expenses['expenses'] is List) {
        _expenses
          ..clear()
          ..addAll((expenses['expenses'] as List)
              .whereType<Map>()
              .map((e) => expenseFromApi(e.cast<String, dynamic>())));
      }
      final customers = await _tryRead('/api/v1/customers', q);
      if (customers is Map && customers['customers'] is List) {
        _customers
          ..clear()
          ..addAll((customers['customers'] as List)
              .whereType<Map>()
              .map((c) => customerFromApi(c.cast<String, dynamic>())));
      }
      final inventory = await _tryRead('/api/v1/inventory', q);
      if (inventory is Map && inventory['inventory'] is List) {
        _inventory
          ..clear()
          ..addAll((inventory['inventory'] as List)
              .whereType<Map>()
              .map((i) => inventoryItemFromApi(i.cast<String, dynamic>())));
      }
      final suppliers = await _tryRead('/api/v1/suppliers', q);
      if (suppliers is Map && suppliers['suppliers'] is List) {
        _suppliers
          ..clear()
          ..addAll((suppliers['suppliers'] as List)
              .whereType<Map>()
              .map((s) => supplierFromApi(s.cast<String, dynamic>())));
      }
      final purchases = await _tryRead('/api/v1/purchases', q);
      if (purchases is Map && purchases['purchases'] is List) {
        _purchases
          ..clear()
          ..addAll((purchases['purchases'] as List)
              .whereType<Map>()
              .map((p) => purchaseFromApi(p.cast<String, dynamic>())));
      }
      final shifts = await _tryRead('/api/v1/shifts', q);
      if (shifts is Map && shifts['shifts'] is List) {
        _shiftHistory
          ..clear()
          ..addAll((shifts['shifts'] as List)
              .whereType<Map>()
              .map((s) => shiftFromApi(s.cast<String, dynamic>()))
              .where((s) => s.isClosed));
      }
      // Overall revenue dashboard is admin-only — skip for every other role
      // so hydrate never trips a 403 (which would surface as a sync error).
      if (_currentStaff?.role == StaffRole.admin) {
        final dash = await _tryRead('/api/v1/reports/dashboard', q);
        if (dash is Map) {
          _serverDashboard = dashboardReportFromApi(dash.cast<String, dynamic>());
        }
      }
      _lastSyncAt = DateTime.now();
      _lastSyncError = null;
      _pendingSyncCount = _sync?.pending ?? 0;
    } on NetworkException {
      _lastSyncError = 'Server unreachable — running on cached data';
    } finally {
      _hydrating = false;
      notifyListeners();
    }
  }

  void _rebuildCategories() {
    final cats = _menuItems
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

  Map<String, dynamic> _bodyOf(Map<String, dynamic> p) {
    final body = Map<String, dynamic>.from(p)
      ..remove('__key')
      ..remove('local_id')
      ..remove('local_item_id');
    return body;
  }

  void _registerOps() {
    final api = _api!;
    final sync = _sync!;

    sync.register('order.create', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/orders',
        query: {'outlet_id': _currentOutlet.id},
        body: {
          'type': p['type'],
          'client_id': p['local_id'],
          if (p['table_id'] != null) 'table_id': p['table_id'],
          if (p['customer_name'] != null) 'customer_name': p['customer_name'],
          if (p['customer_phone'] != null) 'customer_phone': p['customer_phone'],
          if (p['delivery_address'] != null) 'delivery_address': p['delivery_address'],
          if (p['guest_count'] != null) 'guest_count': p['guest_count'],
          if (p['order_note'] != null) 'order_note': p['order_note'],
        },
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('order.patch', (p) async {
      final resp = await api.request(
        'PATCH',
        '/api/v1/orders/${p['order_id']}',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('order.add_item', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/orders/${p['order_id']}/items',
        query: {'outlet_id': _currentOutlet.id},
        body: {
          'menu_item_id': p['menu_item_id'],
          'client_id': p['local_item_id'],
          if (p['variant_id'] != null) 'variant_id': p['variant_id'],
          'quantity': p['quantity'] ?? 1,
          if (p['note'] != null) 'note': p['note'],
          if (p['modifiers'] is List && (p['modifiers'] as List).isNotEmpty)
            'modifiers': (p['modifiers'] as List)
                .map((m) => {'modifier_item_id': m})
                .toList(),
        },
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('item.qty', (p) async {
      final resp = await api.request(
        'PATCH',
        '/api/v1/orders/${p['order_id']}/items/${p['item_id']}',
        query: {'outlet_id': _currentOutlet.id},
        body: {'quantity': p['quantity'] ?? 1},
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('item.cancel', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/orders/${p['order_id']}/items/${p['item_id']}/cancel',
        query: {'outlet_id': _currentOutlet.id},
        body: {'reason': p['reason'] ?? 'Cancelled'},
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('kot.fire', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/orders/${p['order_id']}/kot',
        query: {'outlet_id': _currentOutlet.id},
        body: <String, dynamic>{},
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('kot.status', (p) async {
      final resp = await api.request(
        'PATCH',
        '/api/v1/kots/${p['kot_id']}',
        query: {'outlet_id': _currentOutlet.id},
        body: {'status': p['status']},
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('order.pay', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/orders/${p['order_id']}/pay',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('order.refund', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/orders/${p['order_id']}/refund',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      if (resp is Map && resp['order'] is Map) {
        return (resp['order'] as Map).cast<String, dynamic>();
      }
      return null;
    });

    sync.register('shift.open', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/shifts/open',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('shift.close', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/shifts/current/close',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('cash.move', (p) async {
      await api.request(
        'POST',
        '/api/v1/shifts/current/cash-move',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      return null;
    });

    sync.register('expense.create', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/expenses',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('expense.delete', (p) async {
      await api.request(
        'DELETE',
        '/api/v1/expenses/${p['expense_id']}',
        query: {'outlet_id': _currentOutlet.id},
      );
      return null;
    });

    sync.register('customer.create', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/customers',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('credit.book', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/customers/${p['customer_id']}/credit',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('stock.adjust', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/inventory/${p['item_id']}/adjust',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('table.status', (p) async {
      final resp = await api.request(
        'PATCH',
        '/api/v1/tables/${p['table_id']}',
        query: {'outlet_id': _currentOutlet.id},
        body: {'status': p['status']},
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('table.patch', (p) async {
      final resp = await api.request(
        'PATCH',
        '/api/v1/tables/${p['table_id']}',
        query: {'outlet_id': _currentOutlet.id},
        body: {'floor': p['floor']},
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('table.move', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/tables/${p['from_table_id']}/move',
        query: {'outlet_id': _currentOutlet.id},
        body: {'to_table_id': p['to_table_id']},
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('table.merge', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/tables/${p['primary_table_id']}/merge',
        query: {'outlet_id': _currentOutlet.id},
        body: {'secondary_table_id': p['secondary_table_id']},
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('table.unmerge', (p) async {
      await api.request(
        'POST',
        '/api/v1/tables/${p['table_id']}/unmerge',
        query: {'outlet_id': _currentOutlet.id},
        body: <String, dynamic>{},
      );
      return null;
    });

    sync.register('settings.update', (p) async {
      await api.request(
        'PUT',
        '/api/v1/settings',
        query: {'outlet_id': _currentOutlet.id},
        body: p,
      );
      return null;
    });

    // ---- Back-office ops (W2/W3/W4/W5/W11) — manager-gated server-side ----

    sync.register('menu.create', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/menu',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('menu.update', (p) async {
      final resp = await api.request(
        'PATCH',
        '/api/v1/menu/${p['menu_item_id']}',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('menu.delete', (p) async {
      await api.request(
        'DELETE',
        '/api/v1/menu/${p['menu_item_id']}',
        query: {'outlet_id': _currentOutlet.id},
      );
      return null;
    });

    sync.register('staff.create', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/staff',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('staff.patch', (p) async {
      final resp = await api.request(
        'PATCH',
        '/api/v1/staff/${p['staff_id']}',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('inventory.create', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/inventory',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('supplier.create', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/suppliers',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('purchase.create', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/purchases',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
        idempotencyKey: p['__key']?.toString(),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('purchase.patch', (p) async {
      final resp = await api.request(
        'PATCH',
        '/api/v1/purchases/${p['purchase_id']}',
        query: {'outlet_id': _currentOutlet.id},
        body: {'status': p['status']},
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });

    sync.register('table.create', (p) async {
      final resp = await api.request(
        'POST',
        '/api/v1/tables',
        query: {'outlet_id': _currentOutlet.id},
        body: _bodyOf(p),
      );
      return resp is Map ? resp.cast<String, dynamic>() : null;
    });
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

  // Active User / Session
  Staff? _currentStaff;
  Staff? get currentStaff => _currentStaff;

  Outlet _currentOutlet = Outlet(
    id: 'out-01',
    name: 'Baner Outlet',
    address: 'Plot 42, High Street, Baner, Pune - 411045',
    terminal: 'POS-01',
    isOnline: true,
    gstin: '27AAAAA0000A1Z5',
    fssai: '11521000000123',
    phone: '+91 98765 43210',
  );
  Outlet get currentOutlet => _currentOutlet;

  final List<Outlet> _outlets = [
    Outlet(
      id: 'out-01',
      name: 'Baner Outlet',
      address: 'Plot 42, High Street, Baner, Pune - 411045',
      terminal: 'POS-01',
      isOnline: true,
      gstin: '27AAAAA0000A1Z5',
      fssai: '11521000000123',
      phone: '+91 98765 43210',
    ),
    Outlet(
      id: 'out-02',
      name: 'Kothrud Outlet',
      address: 'Shop 12, Paud Road, Kothrud, Pune',
      terminal: 'POS-02',
      isOnline: true,
      gstin: '27AAAAA0000A1Z5',
      fssai: '11521000000124',
      phone: '+91 98765 43211',
    ),
  ];
  List<Outlet> get outlets => _outlets;

  void selectOutlet(Outlet outlet) => _switchOutlet(outlet);

  // Staff Directory & Authentication
  final List<Staff> _staffList = [
    Staff(
      id: 'st-01',
      name: 'Rahul Sharma',
      role: StaffRole.cashier,
      pin: '1234',
      avatarUrl: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100',
      mobile: '+91 98220 11223',
    ),
    Staff(
      id: 'st-02',
      name: 'Priya Joshi',
      role: StaffRole.manager,
      pin: '9999',
      avatarUrl: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100',
      mobile: '+91 98220 22334',
    ),
    Staff(
      id: 'st-03',
      name: 'Vikram Singh',
      role: StaffRole.admin,
      pin: '0000',
      avatarUrl: 'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=100',
      mobile: '+91 98220 33445',
    ),
    Staff(
      id: 'st-04',
      name: 'Amit Deshmukh',
      role: StaffRole.waiter,
      pin: '1111',
      avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100',
      mobile: '+91 98220 44556',
    ),
    Staff(
      id: 'st-05',
      name: 'Rohan Patil',
      role: StaffRole.waiter,
      pin: '2222',
      avatarUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100',
      mobile: '+91 98220 55667',
    ),
    Staff(
      id: 'st-06',
      name: 'Chef Sharma',
      role: StaffRole.kitchen,
      pin: '5555',
      avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100',
      mobile: '+91 98220 66778',
    ),
  ];
  List<Staff> get staffList => List.unmodifiable(_staffList);

  /// Server-first login. On success the PIN is cached as a salted hash
  /// (PinVault) so THIS terminal can authenticate that staff offline. When
  /// the server is unreachable, verification falls back to the vault —
  /// plaintext demo PINs are only used in demo mode (apiEnabled = false).
  Future<bool> loginStaffById(String staffId, String pin) async {
    if (apiEnabled && _api != null) {
      try {
        final resp = await _api!.login(staffId, pin, _currentOutlet.id);
        final serverStaff = resp['staff'] is Map ? (resp['staff'] as Map).cast<String, dynamic>() : null;
        // Cache the server-verified PIN hash for offline use (caveat fix).
        unawaited(_pinVault!.remember(
          staffId: staffId,
          name: (serverStaff != null && serverStaff['name'] is String)
              ? serverStaff['name'] as String
              : (_staffList.where((s) => s.id == staffId).firstOrNull?.name ?? 'Staff'),
          role: (serverStaff != null && serverStaff['role'] is String)
              ? serverStaff['role'] as String
              : (_staffList.where((s) => s.id == staffId).firstOrNull?.role.name ?? 'waiter'),
          pin: pin,
        ));
        final matched = _staffList.where((s) => s.id == staffId).firstOrNull;
        _currentStaff = matched ?? staffFromApi(serverStaff ?? {});
        _applyLoginEntitlement(resp);
        _isOfflineMode = false;
        _lastSyncError = null;
        notifyListeners();
        unawaited(_postLoginSync());
        return true;
      } on ApiException {
        return false;
      } on NetworkException {
        _isOfflineMode = true;
      }
    }
    if (apiEnabled) {
      // Offline + API mode: only PINs previously verified by the server on
      // THIS terminal can pass.
      final cached = await _pinVault!.verifyStaff(staffId, pin);
      if (cached != null) {
        _currentStaff = cached;
        notifyListeners();
        unawaited(_postLoginSync());
        return true;
      }
      return false;
    }
    try {
      final staff = _staffList.firstWhere(
        (s) => s.id == staffId && s.pin == pin && s.isActive,
      );
      _currentStaff = staff;
      notifyListeners();
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
    if (apiEnabled && _api != null) {
      unawaited(_api!.logout());
      unawaited(_realtime?.dispose());
      _realtime = null;
      _api!.session = null;
      _persistSession(null);
    }
    _currentStaff = null;
    // Forget pending "order ready" alerts and home position for the next
    // staff member on this terminal.
    _readyAlerts.clear();
    _readyAlertTick = 0;
    _currentNavIndex = 0;
    notifyListeners();
  }

  /// FR-A3 manager gate. Online: verifies against the server's bcrypt PIN
  /// store (POST /auth/verify-manager-pin) and caches the verified PIN hash
  /// (PinVault). Offline — or when the session can no longer authenticate —
  /// falls back to vault entries cached on this terminal (demo mode: seed
  /// list). Returns the authorized manager identity, or null.
  Future<Staff?> verifyManagerPin(String pin) async {
    if (apiEnabled && _api != null) {
      try {
        final staffMap = await _api!.verifyManagerPin(pin);
        if (staffMap != null) {
          final manager = staffFromApi(staffMap);
          // Cache the server-verified manager PIN hash for offline gates.
          unawaited(_pinVault!.remember(
            staffId: manager.id,
            name: manager.name,
            role: manager.role.name,
            pin: pin,
          ));
          return manager;
        }
        return null;
      } on NetworkException {
        // offline: fall through to the vault
      } on ApiException catch (e) {
        if (e.status != 401) {
          return null; // definitive server rejection — never authorize
        }
        // 401 (dead session) ≈ offline: fall through to the vault
      }
      final cached = await _pinVault!.verifyAnyManager(pin);
      return cached;
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

  void openShift({
    required double openingCash,
    String? notes,
    CashDenomination? denominations,
  }) {
    final shift = Shift(
      id: 'SH-${DateTime.now().millisecondsSinceEpoch}',
      staffId: _currentStaff?.id ?? 'st-01',
      staffName: _currentStaff?.name ?? 'Staff',
      startedAt: DateTime.now(),
      openingCash: openingCash,
      openingNotes: notes,
      closingDenominations: denominations,
    );
    _currentShift = shift;
    notifyListeners();
    _sync?.push('shift.open', {
      'local_id': shift.id,
      'opening_paise': toPaise(openingCash),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (denominations != null) 'denominations': denominationsToApi(denominations),
    });
  }

  void closeShift({
    required double actualCash,
    String? notes,
    CashDenomination? denominations,
  }) {
    if (_currentShift != null) {
      _currentShift!.closedAt = DateTime.now();
      _currentShift!.actualCashClosed = actualCash;
      _currentShift!.closingNotes = notes;
      _currentShift!.closingDenominations = denominations;
      _currentShift!.isClosed = true;
      _shiftHistory.insert(0, _currentShift!);
      _currentShift = null;
      notifyListeners();
      _sync?.push('shift.close', {
        'counted_paise': toPaise(actualCash),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (denominations != null) 'denominations': denominationsToApi(denominations),
      });
    }
  }

  // Cash In / Out
  final List<CashTransaction> _cashTransactions = [];
  List<CashTransaction> get cashTransactions => _cashTransactions;

  void addCashIn({required double amount, required String reason, String? reference}) {
    if (amount <= 0) return;
    final tx = CashTransaction(
      id: 'CIN-${DateTime.now().millisecondsSinceEpoch}',
      type: CashFlowType.cashIn,
      amount: amount,
      reason: reason,
      reference: reference,
      timestamp: DateTime.now(),
      staffName: _currentStaff?.name ?? 'Staff',
    );
    _cashTransactions.insert(0, tx);
    _currentShift?.cashIn += amount;
    notifyListeners();
    _sync?.push('cash.move', {
      'type': 'cash_in',
      'amount_paise': toPaise(amount),
      'reason': reason,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    });
  }

  void addCashOut({required double amount, required String reason, String? reference}) {
    if (amount <= 0) return;
    final tx = CashTransaction(
      id: 'COUT-${DateTime.now().millisecondsSinceEpoch}',
      type: CashFlowType.cashOut,
      amount: amount,
      reason: reason,
      reference: reference,
      timestamp: DateTime.now(),
      staffName: _currentStaff?.name ?? 'Staff',
    );
    _cashTransactions.insert(0, tx);
    _currentShift?.cashOut += amount;
    notifyListeners();
    _sync?.push('cash.move', {
      'type': 'cash_out',
      'amount_paise': toPaise(amount),
      'reason': reason,
      if (reference != null && reference.isNotEmpty) 'reference': reference,
    });
  }

  // Tables
  String _selectedFloor = 'All';
  String get selectedFloor => _selectedFloor;
  void setFloor(String floor) {
    _selectedFloor = floor;
    notifyListeners();
  }

  final List<RestaurantTable> _tables = [
    RestaurantTable(id: 't-01', tableNumber: 'T01', seats: 2, floor: 'Ground Floor', status: TableStatus.available),
    RestaurantTable(id: 't-02', tableNumber: 'T02', seats: 4, floor: 'Ground Floor', status: TableStatus.occupied, currentOrderAmount: 850.0, runningMinutes: 24, guestCount: 3, assignedWaiter: 'Rahul'),
    RestaurantTable(id: 't-03', tableNumber: 'T03', seats: 4, floor: 'Ground Floor', status: TableStatus.reserved, guestCount: 4),
    RestaurantTable(id: 't-04', tableNumber: 'T04', seats: 6, floor: 'Ground Floor', status: TableStatus.billing, currentOrderAmount: 2450.0, runningMinutes: 52, guestCount: 5, assignedWaiter: 'Amit'),
    RestaurantTable(id: 't-05', tableNumber: 'T05', seats: 4, floor: 'Ground Floor', status: TableStatus.available),
    RestaurantTable(id: 't-06', tableNumber: 'T06', seats: 4, floor: 'Ground Floor', status: TableStatus.available),
    RestaurantTable(id: 't-07', tableNumber: 'T07', seats: 2, floor: 'First Floor', status: TableStatus.available),
    RestaurantTable(id: 't-08', tableNumber: 'T08', seats: 6, floor: 'First Floor', status: TableStatus.occupied, currentOrderAmount: 1650.0, runningMinutes: 18, guestCount: 4, assignedWaiter: 'Rohan'),
    RestaurantTable(id: 't-09', tableNumber: 'T09', seats: 8, floor: 'First Floor', status: TableStatus.available),
    RestaurantTable(id: 't-10', tableNumber: 'T10', seats: 4, floor: 'Outdoor', status: TableStatus.cleaning),
    RestaurantTable(id: 't-11', tableNumber: 'T11', seats: 2, floor: 'Outdoor', status: TableStatus.available),
    RestaurantTable(id: 't-12', tableNumber: 'T12', seats: 4, floor: 'Outdoor', status: TableStatus.available),
  ];
  List<RestaurantTable> get tables => List.unmodifiable(_tables);

  List<RestaurantTable> get filteredTables {
    if (_selectedFloor == 'All') return List.unmodifiable(_tables);
    return List.unmodifiable(_tables.where((t) => t.floor == _selectedFloor));
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
    _sync?.push('table.status', {
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
      final existing = _orders.firstWhere(
        (o) => o.id == table.activeOrderId,
        orElse: () => _createNewOrderForTable(table),
      );
      _activeOrder = existing;
    } else {
      _activeOrder = _createNewOrderForTable(table);
    }
    notifyListeners();
  }

  RestaurantOrder _createNewOrderForTable(RestaurantTable table) {
    _orderCounter++;
    final order = RestaurantOrder(
      id: 'ord-${DateTime.now().millisecondsSinceEpoch}',
      orderNumber: 'ORD-$_orderCounter',
      orderType: OrderType.dineIn,
      tableId: table.id,
      tableNumber: table.tableNumber,
      createdAt: DateTime.now(),
      waiterName: table.assignedWaiter ?? _currentStaff?.name ?? 'Staff',
      guestCount: table.guestCount > 0 ? table.guestCount : 2,
      items: [],
      taxPercent: _settings.gstPercentage,
      isTaxInclusive: _settings.isGstInclusive,
    );
    _pushOrderCreate(order);
    return order;
  }

  void _pushOrderCreate(RestaurantOrder order) {
    _sync?.push('order.create', {
      'local_id': order.id,
      'type': orderTypeToApi(order.orderType),
      if (order.tableId != null) 'table_id': order.tableId,
      if (order.customerName != null && order.customerName!.isNotEmpty)
        'customer_name': order.customerName,
      if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
        'customer_phone': order.customerPhone,
      if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty)
        'delivery_address': order.deliveryAddress,
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
    _sync?.push('order.add_item', {
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
    _sync?.push('item.qty', {
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
    _sync?.push('table.move', {
      'from_table_id': fromTableId,
      'to_table_id': toTableId,
    });
  }

  void mergeTables(String primaryTableId, String secondaryTableId) {
    final primary = _tables.firstWhere(
      (t) => t.id == primaryTableId,
      orElse: () => throw StateError('Primary table not found'),
    );
    final secondary = _tables.firstWhere(
      (t) => t.id == secondaryTableId,
      orElse: () => throw StateError('Secondary table not found'),
    );
    if (primary.id == secondary.id) return;

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
    _sync?.push('table.merge', {
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
    _sync?.push('table.unmerge', {'table_id': tableId});
  }

  void assignWaiterToTable(String tableId, String waiterName) {
    final table = _tables.where((t) => t.id == tableId).firstOrNull;
    if (table == null) return;
    table.assignedWaiter = waiterName;
    if (_activeOrder != null && _activeOrder!.tableId == tableId) {
      _activeOrder!.waiterName = waiterName;
    }
    notifyListeners();
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

  final List<String> categories = [
    'All',
    'Starters',
    'Soups',
    'Main Course',
    'Biryani',
    'Chinese',
    'Pizza',
    'Drinks',
    'Desserts',
  ];

  final List<MenuItem> _menuItems = [
    MenuItem(
      id: 'm-01',
      name: 'Paneer Tikka',
      category: 'Starters',
      price: 280.0,
      isVeg: true,
      imageUrl: 'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?w=300',
      description: 'Marinated cottage cheese char-grilled with capsicum & onions.',
      isBestseller: true,
      modifierGroups: [
        ModifierGroup(
          id: 'mg-01',
          name: 'Spice Level',
          isMultiSelect: false,
          isRequired: true,
          items: [
            ModifierItem(id: 'sp-1', name: 'Medium Spicy', price: 0, isSelected: true),
            ModifierItem(id: 'sp-2', name: 'Extra Spicy', price: 0),
            ModifierItem(id: 'sp-3', name: 'Mild / Jain', price: 0),
          ],
        ),
        ModifierGroup(
          id: 'mg-02',
          name: 'Add-ons',
          isMultiSelect: true,
          items: [
            ModifierItem(id: 'ad-1', name: 'Extra Mint Chutney', price: 20),
            ModifierItem(id: 'ad-2', name: 'Laccha Onions', price: 15),
            ModifierItem(id: 'ad-3', name: 'Extra Butter Coat', price: 30),
          ],
        ),
      ],
    ),
    MenuItem(
      id: 'm-02',
      name: 'Chicken Tandoori',
      category: 'Starters',
      price: 360.0,
      isVeg: false,
      imageUrl: 'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?w=300',
      description: 'Whole chicken cut pieces cured in aromatic tandoori masala.',
      isBestseller: true,
      variants: [
        ProductVariant(id: 'v-c1', name: 'Half (4 pcs)', price: 240),
        ProductVariant(id: 'v-c2', name: 'Full (8 pcs)', price: 420),
      ],
    ),
    MenuItem(
      id: 'm-03',
      name: 'Tomato Dhaniya Shorba',
      category: 'Soups',
      price: 160.0,
      isVeg: true,
      imageUrl: 'https://images.unsplash.com/photo-1547592166-23ac45744acd?w=300',
      description: 'Fresh plum tomato broth spiced with fresh coriander and cumin.',
    ),
    MenuItem(
      id: 'm-04',
      name: 'Butter Chicken',
      category: 'Main Course',
      price: 350.0,
      isVeg: false,
      imageUrl: 'https://images.unsplash.com/photo-1603894584373-5ac82b2ae398?w=300',
      description: 'Slow-cooked chicken pieces simmered in silky buttery tomato gravy.',
      isBestseller: true,
    ),
    MenuItem(
      id: 'm-05',
      name: 'Dal Makhani',
      category: 'Main Course',
      price: 240.0,
      isVeg: true,
      imageUrl: 'https://images.unsplash.com/photo-1546833999-b9f581a1996d?w=300',
      description: 'Black lentils overnight slow cooked with butter and fresh cream.',
      isBestseller: true,
    ),
    MenuItem(
      id: 'm-06',
      name: 'Butter Naan',
      category: 'Main Course',
      price: 50.0,
      isVeg: true,
      imageUrl: 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=300',
      description: 'Crisp, pillowy leavened flatbread brushed with salted butter.',
    ),
    MenuItem(
      id: 'm-07',
      name: 'Veg Dum Biryani',
      category: 'Biryani',
      price: 260.0,
      isVeg: true,
      imageUrl: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=300',
      description: 'Long grain basmati rice layered with garden vegetables and saffron.',
    ),
    MenuItem(
      id: 'm-08',
      name: 'Chicken Dum Biryani',
      category: 'Biryani',
      price: 330.0,
      isVeg: false,
      imageUrl: 'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=300',
      description: 'Hyderabadi style slow dum cooked aromatic chicken biryani.',
      isBestseller: true,
    ),
    MenuItem(
      id: 'm-09',
      name: 'Margherita Pizza',
      category: 'Pizza',
      price: 199.0,
      isVeg: true,
      imageUrl: 'https://images.unsplash.com/photo-1604382354936-07c5d9983bd3?w=300',
      description: 'Classic stone-baked sourdough with San Marzano tomatoes and mozzarella.',
      variants: [
        ProductVariant(id: 'p-reg', name: 'Regular', price: 199),
        ProductVariant(id: 'p-med', name: 'Medium', price: 299),
        ProductVariant(id: 'p-lrg', name: 'Large', price: 399),
      ],
      modifierGroups: [
        ModifierGroup(
          id: 'mg-pz1',
          name: 'Extra Toppings',
          isMultiSelect: true,
          items: [
            ModifierItem(id: 'top-1', name: 'Extra Cheese', price: 50),
            ModifierItem(id: 'top-2', name: 'Jalapeño', price: 30),
            ModifierItem(id: 'top-3', name: 'Mushroom', price: 40),
            ModifierItem(id: 'top-4', name: 'Black Olives', price: 35),
          ],
        ),
        ModifierGroup(
          id: 'mg-pz2',
          name: 'Crust & Bake',
          isMultiSelect: false,
          items: [
            ModifierItem(id: 'bk-1', name: 'Normal Bake', price: 0, isSelected: true),
            ModifierItem(id: 'bk-2', name: 'Well Done / Crispy', price: 0),
          ],
        ),
      ],
    ),
    MenuItem(
      id: 'm-10',
      name: 'Crispy Veg Chilli',
      category: 'Chinese',
      price: 220.0,
      isVeg: true,
      imageUrl: 'https://images.unsplash.com/photo-1585032226651-759b368d7246?w=300',
      description: 'Crisp wok tossed exotic vegetables in dark garlic soya glaze.',
    ),
    MenuItem(
      id: 'm-11',
      name: 'Fresh Lime Soda',
      category: 'Drinks',
      price: 90.0,
      isVeg: true,
      imageUrl: 'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=300',
      description: 'Fresh squeezed lime with soda or water (Sweet/Salt/Mix).',
    ),
    MenuItem(
      id: 'm-12',
      name: 'Gulab Jamun (2 Pcs)',
      category: 'Desserts',
      price: 110.0,
      isVeg: true,
      imageUrl: 'https://images.unsplash.com/photo-1541781774459-bb2af2f05b55?w=300',
      description: 'Warm golden milk dumplings soaked in fragrant cardamom rose syrup.',
    ),
  ];
  List<MenuItem> get menuItems => List.unmodifiable(_menuItems);

  List<MenuItem> get filteredMenuItems {
    return _menuItems.where((item) {
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
  int _orderCounter = 1044;
  RestaurantOrder? _activeOrder;
  RestaurantOrder? get activeOrder => _activeOrder;

  void startNewOrder(OrderType type, {String? customerName, String? customerPhone, String? address}) {
    _orderCounter++;
    // Mirror the outlet settings defaults (same rules the server applies on
    // order create) so offline-created orders bill identically once synced.
    _activeOrder = RestaurantOrder(
      id: 'ord-${DateTime.now().millisecondsSinceEpoch}',
      orderNumber: 'ORD-$_orderCounter',
      orderType: type,
      createdAt: DateTime.now(),
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: address,
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
  }) {
    if (_activeOrder == null) {
      startNewOrder(OrderType.dineIn);
    }

    // Check if same item with same variant and modifiers exists.
    // itemNote participates in the identity so different cooking notes
    // don't merge into one line (and lose a note).
    final existingIndex = _activeOrder!.items.indexWhere(
      (i) =>
          !i.isCancelled &&
          i.menuItem.id == item.id &&
          i.itemNote == note &&
          i.selectedVariant?.id == variant?.id &&
          _areModifiersIdentical(i.selectedModifiers, modifiers),
    );

    if (existingIndex != -1) {
      _activeOrder!.items[existingIndex].quantity += 1;
      _pushItemQty(_activeOrder!, _activeOrder!.items[existingIndex]);
    } else {
      final newItem = OrderItem(
        id: 'item-${DateTime.now().millisecondsSinceEpoch}-${_activeOrder!.items.length}',
        menuItem: item,
        selectedVariant: variant,
        selectedModifiers: modifiers.map((m) => m.copy()).toList(),
        quantity: 1,
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
        _sync?.push('item.qty', {
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
      _sync?.push('item.qty', {
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
      _sync?.push('order.patch', {
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
      if (waiter != null) _activeOrder!.waiterName = waiter;
      notifyListeners();
      _sync?.push('order.patch', {
        'order_id': _activeOrder!.id,
        'guest_count': count,
        if (customerName != null && customerName.isNotEmpty) 'customer_name': customerName,
        if (customerPhone != null && customerPhone.trim().isNotEmpty)
          'customer_phone': customerPhone.trim(),
      });
    } else {
      notifyListeners();
    }
    if (_selectedTable != null) {
      _selectedTable!.guestCount = count;
      if (waiter != null) _selectedTable!.assignedWaiter = waiter;
    }
  }

  // KOT System
  int _kotCounter = 1203;
  final List<KitchenOrderTicket> _kots = [];
  List<KitchenOrderTicket> get kots => List.unmodifiable(_kots);

  KitchenOrderTicket? sendKOT() {
    if (_activeOrder == null || _activeOrder!.items.isEmpty) return null;

    final unsentItems = _activeOrder!.items.where((i) => !i.isKOTSent && !i.isCancelled).toList();
    if (unsentItems.isEmpty) return null;

    _kotCounter++;
    final kot = KitchenOrderTicket(
      id: 'kot-${DateTime.now().millisecondsSinceEpoch}',
      kotNumber: 'KOT #$_kotCounter',
      orderId: _activeOrder!.id,
      tableNumber: _activeOrder!.tableNumber ?? _selectedTable?.tableNumber,
      orderType: _activeOrder!.orderType,
      waiterName: _activeOrder!.waiterName ?? _currentStaff?.name ?? 'Staff',
      createdAt: DateTime.now(),
      items: unsentItems.map((i) => i.copy()).toList(),
      specialInstructions: _activeOrder!.orderNote,
      status: KOTStatus.newTicket,
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
    _sync?.push('kot.fire', {'order_id': kot.orderId});
    if (_settings.autoPrintKOT) {
      _printKot(kot);
    }
    return kot;
  }

  void updateKOTStatus(String kotId, KOTStatus newStatus) {
    final kot = _kots.where((k) => k.id == kotId).firstOrNull;
    if (kot == null) return;
    final prevStatus = kot.status;
    kot.status = newStatus;
    notifyListeners();
    _sync?.push('kot.status', {
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

  List<RestaurantOrder> get runningOrders =>
      _orders.where((o) => o.status != OrderStatus.completed && o.status != OrderStatus.cancelled).toList();

  List<RestaurantOrder> get completedTransactions =>
      _orders.where((o) => o.status == OrderStatus.completed).toList();

  void openRunningOrder(RestaurantOrder order) {
    _activeOrder = order;
    if (order.tableId != null) {
      _selectedTable = _tables.firstWhere(
        (t) => t.id == order.tableId,
        orElse: () => _tables.first,
      );
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
    _sync?.push('item.cancel', {
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
    _sync?.push('order.patch', {
      'order_id': _activeOrder!.id,
      if (percent != null) 'discount_percent': percent.clamp(0.0, 100.0),
      if (amount != null) 'discount_paise': toPaise(_activeOrder!.discountAmount),
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
    _sync?.push('order.patch', {
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
  int _invoiceCounter = 1044;

  RestaurantOrder? completePayment({
    required String paymentMethod,
    required double amountPaid,
    List<({String method, double amount})>? splits,
    double? cashTendered,
  }) {
    if (_activeOrder == null) return null;
    final due = _activeOrder!.grandTotal;
    if (amountPaid + 0.005 < due) return null; // reject short payment

    // Split tender: every leg must be non-negative and the allocation must
    // cover the bill. The cash leg may receive more (change), validated by
    // cashTendered.
    final legs = splits ??
        <({String method, double amount})>[(method: paymentMethod, amount: due)];
    double allocated = 0;
    double cashLeg = 0;
    for (final leg in legs) {
      if (leg.amount < -0.005) return null;
      allocated += leg.amount;
      if (leg.method == 'Cash' || leg.method == 'cash') cashLeg += leg.amount;
    }
    if (allocated + 0.005 < due || allocated > amountPaid + 0.005) return null;
    if (splits != null && cashTendered != null && cashTendered + 0.005 < cashLeg) {
      return null; // cash received short of the cash leg
    }

    _invoiceCounter++;
    final completed = _activeOrder!;
    completed.status = OrderStatus.completed;
    completed.paidAt = DateTime.now();
    completed.invoiceNumber = 'INV-$_invoiceCounter';
    completed.paymentMethod = paymentMethod;
    // Record what the customer actually handed over (includes cash change);
    // shift tender splits book only the bill allocation.
    completed.totalPaid = splits == null ? amountPaid : allocated;

    // Update Shift Sales by tender per leg (enum-safe).
    if (_currentShift != null) {
      for (final leg in legs) {
        switch (PaymentMethodX.fromLabel(leg.method)) {
          case PaymentMethod.cash:
            _currentShift!.cashSales += leg.amount;
            break;
          case PaymentMethod.upi:
            _currentShift!.upiSales += leg.amount;
            break;
          case PaymentMethod.card:
            _currentShift!.cardSales += leg.amount;
            break;
        }
      }
    }

    // Free up Table
    if (completed.tableId != null) {
      final table = _tables.where((t) => t.id == completed.tableId).firstOrNull;
      if (table != null) {
        table.status = TableStatus.available;
        table.activeOrderId = null;
        table.currentOrderAmount = 0.0;
        table.runningMinutes = 0;
        table.guestCount = 0;
        table.assignedWaiter = null;
      }
    }

    // Record Customer Spend
    if (completed.customerPhone != null && completed.customerPhone!.isNotEmpty) {
      final normalizedPhone = _normalizePhone(completed.customerPhone!);
      Customer? cust;
      for (final c in _customers) {
        if (_normalizePhone(c.phone) == normalizedPhone) {
          cust = c;
          break;
        }
      }
      cust ??= Customer(
        id: 'cust-${DateTime.now().millisecondsSinceEpoch}',
        name: completed.customerName ?? 'Guest',
        phone: normalizedPhone,
      );
      if (!_customers.contains(cust)) _customers.insert(0, cust);
      cust.visits += 1;
      cust.lifetimeSpend += completed.grandTotal;
      cust.lastVisit = DateTime.now();
    }

    // Keep completed order visible to transactions/refunds even if no KOT was fired
    if (!_orders.any((o) => o.id == completed.id)) {
      _orders.insert(0, completed);
    }

    _activeOrder = null;
    _selectedTable = null;
    notifyListeners();
    _sync?.push('order.pay', {
      'order_id': completed.id,
      'method': paymentMethodToApi(legs.first.method),
      'amount_received_paise': toPaise(amountPaid),
      if (splits != null)
        'splits': [
          for (final leg in splits)
            {
              'method': paymentMethodToApi(leg.method),
              'amount_paise': toPaise(leg.amount),
            }
        ],
    });
    _printReceipt(completed);
    return completed;
  }

  String _normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'\D'), '');

  // Refunds
  /// Returns true when the refund was recorded.
  bool processRefund({
    required String orderId,
    required double amount,
    required String reason,
    required bool isFullRefund,
    String refundMode = 'Cash',
    String? managerPin,
  }) {
    final order = _orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) return false;
    final paid = order.totalPaid > 0 ? order.totalPaid : order.grandTotal;
    if (amount <= 0 || amount > paid + 0.005) return false;
    if (order.status == OrderStatus.cancelled) return false;

    final tender = PaymentMethodX.fromLabel(order.paymentMethod);
    final isCashRefund = refundMode == 'Cash' || tender == PaymentMethod.cash;
    if (isFullRefund) {
      order.status = OrderStatus.cancelled;
    }
    if (isCashRefund) {
      _currentShift?.refundsCash += amount;
    } else {
      _currentShift?.refundsDigital += amount;
    }
    notifyListeners();
    _sync?.push('order.refund', {
      'order_id': orderId,
      'amount_paise': toPaise(amount),
      'reason': reason,
      'is_full_refund': isFullRefund,
      'mode': refundModeToApi(refundMode),
      // FR-A3: refunds are manager-gated server-side.
      if (managerPin != null && managerPin.isNotEmpty) 'manager_pin': managerPin,
    });
    return true;
  }

  // Expenses
  final List<Expense> _expenses = [
    Expense(
      id: 'exp-01',
      title: 'Electricity Bill (Commercial)',
      category: ExpenseCategory.electricity,
      amount: 8200.0,
      date: DateTime.now().subtract(const Duration(days: 2)),
      paymentMethod: 'UPI',
      vendor: 'MSEDCL',
      description: 'Monthly electricity bill for Baner outlet.',
    ),
    Expense(
      id: 'exp-02',
      title: 'Cleaning Supplies & Detergents',
      category: ExpenseCategory.maintenance,
      amount: 1200.0,
      date: DateTime.now().subtract(const Duration(days: 1)),
      paymentMethod: 'Cash',
      vendor: 'CleanCare Enterprise',
    ),
    Expense(
      id: 'exp-03',
      title: 'Commercial LPG Cylinder (2x)',
      category: ExpenseCategory.gas,
      amount: 3600.0,
      date: DateTime.now(),
      paymentMethod: 'Cash',
      vendor: 'Bharat Gas Agency',
    ),
  ];
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
    _sync?.push('expense.create', {
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
    _sync?.push('expense.delete', {'expense_id': id});
  }

  // Customers
  final List<Customer> _customers = [
    Customer(
      id: 'c-01',
      name: 'Satyajit Nikam',
      phone: '+91 98765 11223',
      email: 'satyajit@example.com',
      visits: 8,
      lifetimeSpend: 14200.0,
      lastVisit: DateTime.now().subtract(const Duration(days: 3)),
    ),
    Customer(
      id: 'c-02',
      name: 'Ananya Roy',
      phone: '+91 98765 22334',
      email: 'ananya@example.com',
      visits: 4,
      lifetimeSpend: 6800.0,
      lastVisit: DateTime.now().subtract(const Duration(days: 5)),
    ),
    Customer(
      id: 'c-03',
      name: 'Karan Mehra',
      phone: '+91 98765 33445',
      visits: 2,
      lifetimeSpend: 3100.0,
      outstandingCredit: 500.0,
    ),
  ];
  List<Customer> get customers => List.unmodifiable(_customers);

  void addCustomer(Customer customer) {
    if (customer.phone.trim().isEmpty) return;
    _customers.insert(0, customer);
    notifyListeners();
    _sync?.push('customer.create', {
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
    _sync?.push('credit.book', {
      'customer_id': customerId,
      'kind': kind,
      'amount_paise': toPaise(amount),
      'reason': reason,
    });
    return true;
  }

  // Inventory & Stock
  final List<InventoryItem> _inventory = [
    InventoryItem(id: 'inv-1', name: 'Fresh Paneer', availableStock: 18.0, minStock: 10.0, unit: 'KG', costPerUnit: 320),
    InventoryItem(id: 'inv-2', name: 'Mozzarella Cheese', availableStock: 4.0, minStock: 8.0, unit: 'KG', costPerUnit: 450), // Low stock
    InventoryItem(id: 'inv-3', name: 'Basmati Rice', availableStock: 45.0, minStock: 25.0, unit: 'KG', costPerUnit: 110),
    InventoryItem(id: 'inv-4', name: 'Chicken (Curry Cut)', availableStock: 14.0, minStock: 10.0, unit: 'KG', costPerUnit: 220),
    InventoryItem(id: 'inv-5', name: 'Cooking Butter', availableStock: 3.5, minStock: 6.0, unit: 'KG', costPerUnit: 520), // Low stock
    InventoryItem(id: 'inv-6', name: 'Amul Fresh Cream', availableStock: 12.0, minStock: 5.0, unit: 'Litre', costPerUnit: 180),
  ];
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
    _sync?.push('stock.adjust', {
      'item_id': itemId,
      'delta': change,
      'reason': reason,
    });
  }

  // Suppliers & Purchases
  final List<Supplier> _suppliers = [
    Supplier(id: 'sup-1', name: 'Metro Dairy Farms', mobile: '+91 98221 00112', category: 'Dairy & Paneer', outstanding: 4500),
    Supplier(id: 'sup-2', name: 'Agro Fresh Poultry', mobile: '+91 98221 00223', category: 'Chicken & Eggs', outstanding: 2800),
    Supplier(id: 'sup-3', name: 'Pune Wholesale Spices', mobile: '+91 98221 00334', category: 'Groceries & Rice'),
  ];
  List<Supplier> get suppliers => _suppliers;

  final List<PurchaseRecord> _purchases = [
    PurchaseRecord(
      id: 'pur-1',
      invoiceNumber: 'PUR-8821',
      supplierName: 'Metro Dairy Farms',
      date: DateTime.now().subtract(const Duration(days: 1)),
      totalAmount: 6400.0,
      paymentStatus: 'Paid',
      itemsSummary: '20 KG Paneer, 10L Fresh Cream',
    ),
    PurchaseRecord(
      id: 'pur-2',
      invoiceNumber: 'PUR-8820',
      supplierName: 'Agro Fresh Poultry',
      date: DateTime.now().subtract(const Duration(days: 3)),
      totalAmount: 5200.0,
      paymentStatus: 'Paid',
      itemsSummary: '25 KG Chicken Curry Cut',
    ),
  ];
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

  void updateSettings(RestaurantSettings s) {
    _settings = s;
    notifyListeners();
    // PUT /settings is manager-gated server-side; pushing from a cashier/
    // waiter terminal would only produce a guaranteed 403.
    final role = _currentStaff?.role;
    if (apiEnabled && (role == StaffRole.manager || role == StaffRole.admin)) {
      _sync?.push('settings.update', settingsToApi(s));
    }
  }

  bool get canManage =>
      _currentStaff?.role == StaffRole.manager || _currentStaff?.role == StaffRole.admin;

  // ---- Back-office actions (W2/W3/W4/W5/W11) ----

  void addMenuItem(MenuItem item) {
    _menuItems.add(item);
    _rebuildCategories();
    notifyListeners();
    _sync?.push('menu.create', {
      'local_id': item.id,
      'category_id': item.category,
      'name': item.name,
      if (item.description.isNotEmpty) 'description': item.description,
      'price_paise': toPaise(item.price),
      'is_veg': item.isVeg,
      'image_url': item.imageUrl,
      'is_bestseller': item.isBestseller,
      if (item.variants.isNotEmpty) 'variants': menuVariantsToApi(item.variants),
      if (item.modifierGroups.isNotEmpty)
        'modifier_groups': menuModifierGroupsToApi(item.modifierGroups),
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
    _sync?.push('menu.update', {
      'menu_item_id': item.id,
      'category_id': item.category,
      'name': item.name,
      if (item.description.isNotEmpty) 'description': item.description,
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
    _sync?.push('menu.delete', {'menu_item_id': id});
  }

  void addStaff(Staff staff) {
    _staffList.add(staff);
    notifyListeners();
    _sync?.push('staff.create', {
      'local_id': staff.id,
      'name': staff.name,
      'role': staff.role.name,
      'pin': staff.pin,
      if (staff.avatarUrl.isNotEmpty) 'avatar_url': staff.avatarUrl,
      if (staff.mobile.isNotEmpty) 'mobile': staff.mobile,
    });
  }

  void updateStaff(String id, {String? name, StaffRole? role, bool? isActive, String? pin}) {
    final idx = _staffList.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    final s = _staffList[idx];
    _staffList[idx] = Staff(
      id: s.id,
      name: name ?? s.name,
      role: role ?? s.role,
      pin: (pin != null && pin.isNotEmpty) ? pin : s.pin,
      avatarUrl: s.avatarUrl,
      mobile: s.mobile,
      isActive: isActive ?? s.isActive,
    );
    notifyListeners();
    _sync?.push('staff.patch', {
      'staff_id': id,
      'name': ?name,
      if (role != null) 'role': role.name,
      'is_active': ?isActive,
      'pin': ?((pin != null && pin.isNotEmpty) ? pin : null),
    });
  }

  void addInventoryItem(InventoryItem item) {
    _inventory.add(item);
    notifyListeners();
    _sync?.push('inventory.create', {
      'local_id': item.id,
      'name': item.name,
      'unit': item.unit,
      'stock': item.availableStock,
      'min_stock': item.minStock,
      'cost_paise': toPaise(item.costPerUnit),
    });
  }

  void addSupplier(Supplier supplier) {
    _suppliers.add(supplier);
    notifyListeners();
    _sync?.push('supplier.create', {
      'local_id': supplier.id,
      'name': supplier.name,
      'mobile': supplier.mobile,
      if (supplier.email != null && supplier.email!.isNotEmpty) 'email': supplier.email,
      if (supplier.category.isNotEmpty) 'category': supplier.category,
    });
  }

  void createPurchase({
    required String invoiceNo,
    String? supplierId,
    required String status,
    required double totalAmount,
    required List<Map<String, dynamic>> lines,
  }) {
    final record = PurchaseRecord(
      id: 'pur-${DateTime.now().millisecondsSinceEpoch}',
      invoiceNumber: invoiceNo,
      supplierName: _suppliers.where((s) => s.id == supplierId).firstOrNull?.name ?? '',
      date: DateTime.now(),
      totalAmount: totalAmount,
      paymentStatus: status == 'pending' ? 'Pending' : 'Paid',
      itemsSummary: lines.map((l) => '${l['name']} ×${l['qty']}').join(', '),
    );
    _purchases.insert(0, record);
    notifyListeners();
    _sync?.push('purchase.create', {
      'local_id': record.id,
      'invoice_no': invoiceNo,
      if (supplierId != null && supplierId.isNotEmpty) 'supplier_id': supplierId,
      'status': status,
      'total_paise': toPaise(totalAmount),
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
    _sync?.push('purchase.patch', {'purchase_id': id, 'status': 'paid'});
  }

  /// Moves an existing table to another dining section (its floor name).
  void updateTableSection(String tableId, String section) {
    final name = section.trim();
    final table = _tables.where((t) => t.id == tableId).firstOrNull;
    if (table == null || name.isEmpty || table.floor == name) return;
    table.floor = name;
    notifyListeners();
    _sync?.push('table.patch', {'table_id': table.id, 'floor': name});
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
    _sync?.push('table.create', {
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
    final data = await _api!.request(
      'GET', '/api/v1/customers/$id/credit-log',
      query: {'outlet_id': _currentOutlet.id},
    );
    if (data is Map && data['entries'] is List) {
      return (data['entries'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  /// FR-I1: server-side stock adjustment audit log.
  Future<List<Map<String, dynamic>>> fetchStockAdjustments() async {
    if (!apiEnabled || _api == null || !_sync!.online) return const [];
    final data = await _api!.request(
      'GET', '/api/v1/inventory/adjustments',
      query: {'outlet_id': _currentOutlet.id},
    );
    if (data is Map && data['adjustments'] is List) {
      return (data['adjustments'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
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
      final data = await _api!.request('GET', '/api/v1/reports/shift/$id/zreport');
      return data is Map ? data.cast<String, dynamic>() : null;
    } on ApiException catch (_) {
      return null;
    }
  }

  void _switchOutlet(Outlet outlet) {
    _currentOutlet = outlet;
    notifyListeners();
    if (apiEnabled && _currentStaff != null) {
      unawaited(_postLoginSync());
    }
  }

  // Offline / Sync State
  bool _isOfflineMode = false;
  bool get isOfflineMode =>
      apiEnabled ? !(_sync?.online ?? false) : _isOfflineMode;
  int _pendingSyncCount = 0;
  int get pendingSyncCount => apiEnabled ? (_sync?.pending ?? 0) : _pendingSyncCount;
  bool get realtimeConnected => _realtime?.connected ?? false;

  void toggleOfflineMode() {
    final goingOffline = !isOfflineMode;
    _isOfflineMode = goingOffline;
    _sync?.setForceOffline(goingOffline);
    if (!goingOffline) {
      unawaited(triggerSync());
    } else if (!apiEnabled) {
      _pendingSyncCount = 4;
    }
    notifyListeners();
  }

  Future<void> triggerSync() async {
    if (apiEnabled && _sync != null) {
      final ok = await _sync!.probe();
      if (ok) {
        _lastSyncError = null;
        await hydrateOutlet();
      }
    } else {
      _pendingSyncCount = 0;
    }
    notifyListeners();
  }

  // ---- Printing (P5.1: ESC/POS hooks) ----

  PrinterAdapter get _effectivePrinter =>
      _printer ?? printerFromSetting(_settings.billingPrinter);

  void _printReceipt(RestaurantOrder order) {
    if (!apiEnabled) return;
    if (!_settings.allowReprint && order.invoiceNumber == null) return;
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
      _printerError = 'Printer "${_effectivePrinter.name}": $e';
      notifyListeners();
      return false;
    }
  }

  void _printKot(KitchenOrderTicket kot) {
    if (!apiEnabled) return;
    final setting = _settings.kitchenPrinter.trim().isNotEmpty
        ? _settings.kitchenPrinter
        : _settings.billingPrinter;
    _sendPrint(buildKotBytes(kot, _settings), printerFromSetting(setting));
  }

  void _sendPrint(List<int> bytes, PrinterAdapter adapter) {
    unawaited(() async {
      try {
        await adapter.send(bytes);
        _printerError = null;
      } catch (e) {
        _printerError = 'Printer "${adapter.name}": $e';
      }
      notifyListeners();
    }());
  }

  // Seed sample initial transactions if empty
  void _seedData() {
    if (apiEnabled) {
      // No plaintext PINs on real terminals: the server bcrypt-verifies and
      // offline reuse is handled by PinVault (salted hashes cached per
      // terminal). Demo mode (apiEnabled=false) keeps the seed PINs.
      final blanked = _staffList
          .map((s) => Staff(
                id: s.id,
                name: s.name,
                role: s.role,
                pin: '',
                avatarUrl: s.avatarUrl,
                mobile: s.mobile,
                isActive: s.isActive,
              ))
          .toList();
      _staffList
        ..clear()
        ..addAll(blanked);
    }
    // Start an active shift so the app is instantly usable
    _currentStaff = _staffList.first; // Rahul (Cashier)
    _currentShift = Shift(
      id: 'SH-101',
      staffId: 'st-01',
      staffName: 'Rahul Sharma',
      startedAt: DateTime.now().subtract(const Duration(hours: 4)),
      openingCash: 5000.0,
      cashSales: 4200.0,
      upiSales: 7800.0,
      cardSales: 3400.0,
      expenses: 4800.0,
      cashIn: 1000.0,
      cashOut: 500.0,
    );

    // Seed completed past invoices
    _orders.add(
      RestaurantOrder(
        id: 'ord-seed-1',
        orderNumber: 'ORD-1040',
        orderType: OrderType.dineIn,
        tableId: 't-04',
        tableNumber: 'T04',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        status: OrderStatus.completed,
        customerName: 'Rohit Sharma',
        customerPhone: '+91 99881 22334',
        items: [
          OrderItem(
            id: 'i-s1',
            menuItem: _menuItems[0], // Paneer Tikka
            quantity: 2,
            isKOTSent: true,
          ),
          OrderItem(
            id: 'i-s2',
            menuItem: _menuItems[5], // Butter Naan
            quantity: 4,
            isKOTSent: true,
          ),
        ],
        invoiceNumber: 'INV-1040',
        paidAt: DateTime.now().subtract(const Duration(hours: 2)),
        paymentMethod: 'Cash',
        totalPaid: 798.0,
      ),
    );

    _orders.add(
      RestaurantOrder(
        id: 'ord-seed-2',
        orderNumber: 'ORD-1041',
        orderType: OrderType.takeaway,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        status: OrderStatus.completed,
        customerName: 'Pooja Hegde',
        customerPhone: '+91 99881 33445',
        items: [
          OrderItem(
            id: 'i-s3',
            menuItem: _menuItems[7], // Chicken Biryani
            quantity: 2,
            isKOTSent: true,
          ),
        ],
        invoiceNumber: 'INV-1041',
        paidAt: DateTime.now().subtract(const Duration(hours: 1)),
        paymentMethod: 'UPI',
        totalPaid: 693.0,
      ),
    );

    // Seed active KOT
    _kots.add(
      KitchenOrderTicket(
        id: 'kot-seed-1',
        kotNumber: 'KOT #1201',
        orderId: 'ord-seed-3',
        tableNumber: 'T02',
        orderType: OrderType.dineIn,
        waiterName: 'Rahul',
        createdAt: DateTime.now().subtract(const Duration(minutes: 24)),
        status: KOTStatus.preparing,
        items: [
          OrderItem(id: 'i-k1', menuItem: _menuItems[0], quantity: 1, isKOTSent: true),
          OrderItem(id: 'i-k2', menuItem: _menuItems[4], quantity: 1, isKOTSent: true),
        ],
      ),
    );

    _kots.add(
      KitchenOrderTicket(
        id: 'kot-seed-2',
        kotNumber: 'KOT #1202',
        orderId: 'ord-seed-4',
        tableNumber: 'T08',
        orderType: OrderType.dineIn,
        waiterName: 'Rohan',
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
        status: KOTStatus.newTicket,
        items: [
          OrderItem(id: 'i-k3', menuItem: _menuItems[8], quantity: 2, isKOTSent: true),
          OrderItem(id: 'i-k4', menuItem: _menuItems[10], quantity: 3, isKOTSent: true),
        ],
      ),
    );
  }
}

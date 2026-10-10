/// Wire mapping for every offline-sync op: queued payload → HTTP request.
///
/// The server decodes bodies with `DisallowUnknownFields`, so a stray key
/// (a path id, `local_id`, the op's `outlet_id` scope) turns the whole write
/// into a 400 that the outbox then drops. Bodies are therefore built from an
/// explicit allowlist per op, never by copying the payload. The canonical
/// shapes live in `contracts/sync_ops.json`, which both this file and the Go
/// handlers are tested against.
library;

class OpRequest {
  final String method;
  final String path;

  /// Null for body-less requests (DELETE).
  final Map<String, dynamic>? body;

  /// Whether the server dedupes this op by its Idempotency-Key.
  final bool idempotent;

  const OpRequest(this.method, this.path, this.body, {this.idempotent = false});
}

class _Spec {
  final String method;
  final String Function(Map<String, dynamic> p) path;
  final List<String>? keys;
  final Map<String, String> renames;
  final bool idempotent;

  const _Spec(
    this.method,
    this.path, {
    this.keys = const [],
    this.renames = const {},
    this.idempotent = false,
  });
}

String _id(Map<String, dynamic> p, String key) {
  final v = p[key];
  if (v is! String || v.isEmpty) {
    throw ArgumentError('op payload is missing "$key"');
  }
  return Uri.encodeComponent(v);
}

final Map<String, _Spec> _specs = {
  'order.create': _Spec('POST', (_) => '/api/v1/orders',
      keys: ['type', 'client_id', 'table_id', 'customer_name', 'customer_phone',
        'delivery_address', 'waiter_id', 'waiter_name', 'guest_count', 'order_note'],
      renames: {'local_id': 'client_id'},
      idempotent: true),
  'order.patch': _Spec('PATCH', (p) => '/api/v1/orders/${_id(p, 'order_id')}',
      keys: ['status', 'waiter_id', 'waiter_name', 'order_note', 'guest_count',
        'customer_name', 'customer_phone', 'discount_percent', 'discount_paise',
        'discount_reason', 'service_charge_paise', 'packaging_charge_paise',
        'delivery_charge_paise', 'manager_pin']),
  'order.add_item': _Spec('POST', (p) => '/api/v1/orders/${_id(p, 'order_id')}/items',
      keys: ['menu_item_id', 'client_id', 'variant_id', 'quantity', 'note', 'modifiers'],
      renames: {'local_item_id': 'client_id'},
      idempotent: true),
  'item.qty': _Spec('PATCH',
      (p) => '/api/v1/orders/${_id(p, 'order_id')}/items/${_id(p, 'item_id')}',
      keys: ['quantity', 'manager_pin']),
  'item.cancel': _Spec('POST',
      (p) => '/api/v1/orders/${_id(p, 'order_id')}/items/${_id(p, 'item_id')}/cancel',
      keys: ['reason', 'manager_pin']),
  'kot.fire': _Spec('POST', (p) => '/api/v1/orders/${_id(p, 'order_id')}/kot',
      idempotent: true),
  'kot.status': _Spec('PATCH', (p) => '/api/v1/kots/${_id(p, 'kot_id')}', keys: ['status']),
  'order.pay': _Spec('POST', (p) => '/api/v1/orders/${_id(p, 'order_id')}/pay',
      keys: ['method', 'amount_received_paise', 'splits', 'reference', 'customer_id'],
      idempotent: true),
  'order.refund': _Spec('POST', (p) => '/api/v1/orders/${_id(p, 'order_id')}/refund',
      keys: ['amount_paise', 'reason', 'is_full_refund', 'mode', 'manager_pin'],
      idempotent: true),
  'shift.open': _Spec('POST', (_) => '/api/v1/shifts/open',
      keys: ['opening_paise', 'notes', 'denominations'], idempotent: true),
  'shift.close': _Spec('POST', (_) => '/api/v1/shifts/current/close',
      keys: ['counted_paise', 'notes', 'denominations'], idempotent: true),
  'cash.move': _Spec('POST', (_) => '/api/v1/shifts/current/cash-move',
      keys: ['type', 'amount_paise', 'reason', 'reference', 'at'], idempotent: true),
  'expense.create': _Spec('POST', (_) => '/api/v1/expenses',
      keys: ['title', 'category', 'amount_paise', 'method', 'vendor', 'reference', 'note'],
      idempotent: true),
  'expense.delete': _Spec('DELETE', (p) => '/api/v1/expenses/${_id(p, 'expense_id')}',
      keys: null),
  'customer.create': _Spec('POST', (_) => '/api/v1/customers',
      keys: ['name', 'phone', 'email', 'address'], idempotent: true),
  'credit.book': _Spec('POST', (p) => '/api/v1/customers/${_id(p, 'customer_id')}/credit',
      keys: ['kind', 'amount_paise', 'reason'], idempotent: true),
  'stock.adjust': _Spec('POST', (p) => '/api/v1/inventory/${_id(p, 'item_id')}/adjust',
      keys: ['delta', 'reason'], idempotent: true),
  'table.status': _Spec('PATCH', (p) => '/api/v1/tables/${_id(p, 'table_id')}',
      keys: ['status']),
  'table.patch': _Spec('PATCH', (p) => '/api/v1/tables/${_id(p, 'table_id')}',
      keys: ['floor', 'waiter_id', 'guest_count', 'table_number', 'seats']),
  'table.delete': _Spec('DELETE', (p) => '/api/v1/tables/${_id(p, 'table_id')}', keys: null),
  'table.move': _Spec('POST', (p) => '/api/v1/tables/${_id(p, 'from_table_id')}/move',
      keys: ['to_table_id'], idempotent: true),
  'table.merge': _Spec('POST', (p) => '/api/v1/tables/${_id(p, 'primary_table_id')}/merge',
      keys: ['secondary_table_id'], idempotent: true),
  'table.unmerge': _Spec('POST', (p) => '/api/v1/tables/${_id(p, 'table_id')}/unmerge'),
  'table.create': _Spec('POST', (_) => '/api/v1/tables',
      keys: ['table_number', 'seats', 'floor', 'status'], idempotent: true),
  'settings.update': _Spec('PUT', (_) => '/api/v1/settings',
      keys: ['restaurant_name', 'gst_percent', 'is_gst_inclusive', 'service_percent',
        'packaging_paise', 'delivery_paise', 'auto_print_kot', 'allow_reprint',
        'billing_printer', 'kitchen_printer', 'bar_printer', 'sections', 'upi_id',
        'upi_name', 'upi_qr_image']),
  'outlet.patch': _Spec('PATCH', (p) => '/api/v1/outlets/${_id(p, 'outlet_id')}',
      keys: ['name', 'address', 'phone', 'email', 'gstin', 'fssai', 'timezone']),
  'menu.create': _Spec('POST', (_) => '/api/v1/menu',
      keys: ['category_id', 'name', 'description', 'price_paise', 'is_veg', 'image_url',
        'is_bestseller', 'is_available', 'variants', 'modifier_groups'],
      idempotent: true),
  'menu.update': _Spec('PATCH', (p) => '/api/v1/menu/${_id(p, 'menu_item_id')}',
      keys: ['category_id', 'name', 'description', 'price_paise', 'is_veg', 'image_url',
        'is_bestseller', 'is_available', 'variants', 'modifier_groups']),
  'menu.delete': _Spec('DELETE', (p) => '/api/v1/menu/${_id(p, 'menu_item_id')}',
      keys: null),
  // A staff member's own outlet travels as `staff_outlet_id` in the payload
  // because `outlet_id` is the op's routing scope.
  'staff.create': _Spec('POST', (_) => '/api/v1/staff',
      keys: ['name', 'role', 'pin', 'outlet_id', 'avatar_url', 'mobile'],
      renames: {'staff_outlet_id': 'outlet_id'},
      idempotent: true),
  'staff.patch': _Spec('PATCH', (p) => '/api/v1/staff/${_id(p, 'staff_id')}',
      keys: ['name', 'role', 'outlet_id', 'is_active', 'pin', 'mobile', 'avatar_url'],
      renames: {'staff_outlet_id': 'outlet_id'}),
  'inventory.create': _Spec('POST', (_) => '/api/v1/inventory',
      keys: ['name', 'unit', 'stock', 'min_stock', 'cost_paise', 'batch_no', 'rack_no',
        'purchased_at'],
      idempotent: true),
  'supplier.create': _Spec('POST', (_) => '/api/v1/suppliers',
      keys: ['name', 'mobile', 'email', 'category'], idempotent: true),
  'supplier.payment': _Spec('POST', (p) => '/api/v1/suppliers/${_id(p, 'supplier_id')}/payments',
      keys: ['amount_paise', 'method', 'at', 'reference'], idempotent: true),
  'purchase.create': _Spec('POST', (_) => '/api/v1/purchases',
      keys: ['invoice_no', 'supplier_id', 'status', 'total_paise', 'purchased_at', 'items'],
      idempotent: true),
  'purchase.patch': _Spec('PATCH', (p) => '/api/v1/purchases/${_id(p, 'purchase_id')}',
      keys: ['status']),
};

/// Every op type the outbox knows how to send.
Iterable<String> get knownOpTypes => _specs.keys;

/// Builds the request for [type] from its queued [payload]. Null-valued keys
/// are omitted (the server treats absent as "unchanged"); empty strings are
/// kept because some fields use '' to mean "clear".
OpRequest buildOpRequest(String type, Map<String, dynamic> payload) {
  final spec = _specs[type];
  if (spec == null) throw ArgumentError('unknown op type "$type"');

  final keys = spec.keys;
  Map<String, dynamic>? body;
  if (keys != null) {
    // `outlet_id` is always the routing scope (query param), never body data.
    final source = <String, dynamic>{...payload}..remove('outlet_id');
    spec.renames.forEach((from, to) {
      if (source.containsKey(from)) source[to] = source[from];
    });
    body = {
      for (final k in keys)
        if (source[k] != null) k: source[k],
    };
    if (type == 'order.add_item' && body['modifiers'] is List) {
      final mods = body['modifiers'] as List;
      if (mods.isEmpty) {
        body.remove('modifiers');
      } else {
        body['modifiers'] = [
          for (final m in mods) m is Map ? m : {'modifier_item_id': m},
        ];
      }
    }
  }
  return OpRequest(spec.method, spec.path(payload), body, idempotent: spec.idempotent);
}

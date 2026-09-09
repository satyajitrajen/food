import '../../models/customer_model.dart';
import '../../models/expense_model.dart';
import '../../models/inventory_model.dart';
import '../../models/kot_model.dart';
import '../../models/menu_model.dart';
import '../../models/order_model.dart';
import '../../models/outlet_model.dart';
import '../../models/report_model.dart';
import '../../models/settings_model.dart';
import '../../models/shift_model.dart';
import '../../models/staff_model.dart';
import '../../models/table_model.dart';

/// Money convention: the Go API speaks INTEGER PAISE; the Flutter models
/// speak DOUBLE RUPEES. Conversion happens only here, at the API edge.
int toPaise(double rupees) => (rupees * 100).round();

double toRupees(int paise) => paise / 100.0;

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _double(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

String _str(dynamic v, [String def = '']) => v is String ? v : def;

String? _optStr(dynamic v) => (v is String && v.isNotEmpty) ? v : null;

DateTime? _dt(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  final parsed = DateTime.tryParse(v);
  return parsed?.toLocal();
}

DateTime _dtOrNow(dynamic v) => _dt(v) ?? DateTime.now();

String orderTypeToApi(OrderType t) {
  switch (t) {
    case OrderType.dineIn:
      return 'dine_in';
    case OrderType.takeaway:
      return 'takeaway';
    case OrderType.delivery:
      return 'delivery';
  }
}

OrderType orderTypeFromApi(String s) {
  switch (s) {
    case 'takeaway':
      return OrderType.takeaway;
    case 'delivery':
      return OrderType.delivery;
    default:
      return OrderType.dineIn;
  }
}

OrderStatus orderStatusFromApi(String s) {
  switch (s) {
    case 'preparing':
      return OrderStatus.preparing;
    case 'ready':
      return OrderStatus.ready;
    case 'served':
      return OrderStatus.served;
    case 'billing':
      return OrderStatus.billing;
    case 'completed':
      return OrderStatus.completed;
    case 'cancelled':
      return OrderStatus.cancelled;
    default:
      return OrderStatus.received;
  }
}

KOTStatus kotStatusFromApi(String s) {
  switch (s) {
    case 'preparing':
      return KOTStatus.preparing;
    case 'ready':
      return KOTStatus.ready;
    case 'served':
      return KOTStatus.served;
    case 'cancelled':
      return KOTStatus.cancelled;
    default:
      return KOTStatus.newTicket;
  }
}

String kotStatusToApi(KOTStatus s) {
  switch (s) {
    case KOTStatus.newTicket:
      return 'new';
    case KOTStatus.preparing:
      return 'preparing';
    case KOTStatus.ready:
      return 'ready';
    case KOTStatus.served:
      return 'served';
    case KOTStatus.cancelled:
      return 'cancelled';
  }
}

TableStatus tableStatusFromApi(String s) {
  switch (s) {
    case 'occupied':
      return TableStatus.occupied;
    case 'reserved':
      return TableStatus.reserved;
    case 'billing':
      return TableStatus.billing;
    case 'cleaning':
      return TableStatus.cleaning;
    default:
      return TableStatus.available;
  }
}

String tableStatusToApi(TableStatus s) {
  switch (s) {
    case TableStatus.available:
      return 'available';
    case TableStatus.occupied:
      return 'occupied';
    case TableStatus.reserved:
      return 'reserved';
    case TableStatus.billing:
      return 'billing';
    case TableStatus.cleaning:
      return 'cleaning';
  }
}

String paymentMethodToApi(String label) {
  switch (label) {
    case 'UPI':
      return 'upi';
    case 'Card':
      return 'card';
    default:
      return 'cash';
  }
}

String refundModeToApi(String label) {
  switch (label) {
    case 'UPI':
      return 'upi';
    case 'Original':
      return 'original';
    default:
      return 'cash';
  }
}

String staffRoleFromApi(String s) {
  switch (s) {
    case 'admin':
      return 'admin';
    case 'manager':
      return 'manager';
    case 'cashier':
      return 'cashier';
    default:
      return 'waiter';
  }
}

ExpenseCategory expenseCategoryFromApi(String s) {
  switch (s) {
    case 'rent':
      return ExpenseCategory.rent;
    case 'electricity':
      return ExpenseCategory.electricity;
    case 'gas':
      return ExpenseCategory.gas;
    case 'salary':
      return ExpenseCategory.salary;
    case 'maintenance':
      return ExpenseCategory.maintenance;
    case 'transport':
      return ExpenseCategory.transport;
    case 'raw_materials':
      return ExpenseCategory.rawMaterials;
    default:
      return ExpenseCategory.miscellaneous;
  }
}

String expenseCategoryToApi(ExpenseCategory c) {
  switch (c) {
    case ExpenseCategory.rent:
      return 'rent';
    case ExpenseCategory.electricity:
      return 'electricity';
    case ExpenseCategory.gas:
      return 'gas';
    case ExpenseCategory.salary:
      return 'salary';
    case ExpenseCategory.maintenance:
      return 'maintenance';
    case ExpenseCategory.transport:
      return 'transport';
    case ExpenseCategory.rawMaterials:
      return 'raw_materials';
    case ExpenseCategory.miscellaneous:
      return 'miscellaneous';
  }
}

// ---- Readers (API JSON → Flutter models) ----

Outlet outletFromApi(Map<String, dynamic> j) => Outlet(
      id: _str(j['id']),
      name: _str(j['name']),
      address: _str(j['address']),
      terminal: _str(j['terminal']),
      isOnline: j['is_online'] != false,
      gstin: _str(j['gstin']),
      fssai: _str(j['fssai']),
      phone: _str(j['phone']),
    );

Staff staffFromApi(Map<String, dynamic> j) {
  final role = staffRoleFromApi(_str(j['role']));
  return Staff(
    id: _str(j['id']),
    name: _str(j['name']),
    role: StaffRole.values.firstWhere(
      (r) => r.name == role,
      orElse: () => StaffRole.waiter,
    ),
    pin: '',
    avatarUrl: _str(j['avatar_url']),
    mobile: _str(j['mobile']),
    isActive: j['is_active'] != false,
  );
}

RestaurantTable tableFromApi(Map<String, dynamic> j) {
  final waiterId = _optStr(j['assigned_waiter_id']);
  return RestaurantTable(
    id: _str(j['id']),
    tableNumber: _str(j['table_number']),
    seats: _int(j['seats']),
    floor: _str(j['floor'], 'Ground Floor'),
    status: tableStatusFromApi(_str(j['status'])),
    activeOrderId: _optStr(j['active_order_id']),
    currentOrderAmount: toRupees(_int(j['current_amount_paise'])),
    runningMinutes: _int(j['running_minutes']),
    guestCount: _int(j['guest_count']),
    assignedWaiter: waiterId,
    mergedWithTableId: _optStr(j['merged_with_table_id']),
  );
}

MenuItem menuItemFromApi(Map<String, dynamic> j) => MenuItem(
      id: _str(j['id']),
      name: _str(j['name']),
      category: _str(j['category']),
      price: toRupees(_int(j['price_paise'])),
      isVeg: j['is_veg'] == true,
      imageUrl: _str(j['image_url']),
      description: _str(j['description']),
      isBestseller: j['is_bestseller'] == true,
      isAvailable: j['is_available'] != false,
      variants: (j['variants'] as List? ?? [])
          .whereType<Map>()
          .map((v) => ProductVariant(
                id: _str(v['id']),
                name: _str(v['name']),
                price: toRupees(_int(v['price_paise'])),
              ))
          .toList(),
      modifierGroups: (j['modifier_groups'] as List? ?? [])
          .whereType<Map>()
          .map((g) => ModifierGroup(
                id: _str(g['id']),
                name: _str(g['name']),
                isMultiSelect: g['is_multi_select'] == true,
                isRequired: g['is_required'] == true,
                items: (g['items'] as List? ?? [])
                    .whereType<Map>()
                    .map((m) => ModifierItem(
                          id: _str(m['id']),
                          name: _str(m['name']),
                          price: toRupees(_int(m['price_paise'])),
                        ))
                    .toList(),
              ))
          .toList(),
    );

MenuItem _menuItemForLookup(String id, String name, double price) => MenuItem(
      id: id,
      name: name,
      category: '',
      price: price,
      isVeg: true,
      imageUrl: '',
    );

OrderItem orderItemFromApi(
  Map<String, dynamic> j,
  MenuItem? Function(String id)? menuLookup,
) {
  final menuItemId = _str(j['menu_item_id']);
  final unitPaise = _int(j['unit_paise']);
  final mods = (j['modifiers'] as List? ?? [])
      .whereType<Map>()
      .map((m) => ModifierItem(
            id: _str(m['modifier_item_id']),
            name: _str(m['name']),
            price: toRupees(_int(m['price_paise'])),
            isSelected: true,
          ))
      .toList();
  final modsTotal = mods.fold(0.0, (s, m) => s + m.price);
  final menu = menuLookup?.call(menuItemId);
  ProductVariant? variant;
  final variantId = _optStr(j['variant_id']);
  if (variantId != null) {
    variant = menu?.variants.where((v) => v.id == variantId).firstOrNull ??
        ProductVariant(
          id: variantId,
          name: 'Variant',
          price: toRupees(unitPaise) - modsTotal,
        );
  }
  return OrderItem(
    id: _str(j['id']),
    menuItem: menu ??
        _menuItemForLookup(
          menuItemId,
          _str(j['name'], menuItemId),
          toRupees(unitPaise) - modsTotal,
        ),
    selectedVariant: variant,
    selectedModifiers: mods,
    quantity: _int(j['quantity']),
    itemNote: _optStr(j['note']),
    isKOTSent: j['is_kot_sent'] == true,
    isCancelled: j['is_cancelled'] == true,
    cancelReason: _optStr(j['cancel_reason']),
  );
}

RestaurantOrder orderFromApi(
  Map<String, dynamic> j,
  MenuItem? Function(String id)? menuLookup,
) => RestaurantOrder(
      id: _str(j['id']),
      orderNumber: _str(j['order_number']),
      orderType: orderTypeFromApi(_str(j['type'])),
      tableId: _optStr(j['table_id']),
      tableNumber: _optStr(j['table_number']),
      createdAt: _dtOrNow(j['created_at']),
      status: orderStatusFromApi(_str(j['status'])),
      customerName: _optStr(j['customer_name']),
      customerPhone: _optStr(j['customer_phone']),
      deliveryAddress: _optStr(j['delivery_address']),
      waiterName: _optStr(j['waiter_name']),
      guestCount: _int(j['guest_count']) <= 0 ? 1 : _int(j['guest_count']),
      orderNote: _optStr(j['order_note']),
      items: (j['items'] as List? ?? [])
          .whereType<Map>()
          .map((i) => orderItemFromApi(i.cast<String, dynamic>(), menuLookup))
          .toList(),
      discountPercent: _double(j['discount_percent']),
      discountAmount: toRupees(_int(j['discount_paise'])),
      discountReason: _optStr(j['discount_reason']),
      taxPercent: _double(j['tax_percent']),
      isTaxInclusive: j['is_tax_inclusive'] == true,
      serviceCharge: toRupees(_int(j['service_charge_paise'])),
      packagingCharge: toRupees(_int(j['packaging_charge_paise'])),
      deliveryCharge: toRupees(_int(j['delivery_charge_paise'])),
      invoiceNumber: _optStr(j['invoice_number']),
      paidAt: _dt(j['paid_at']),
      paymentMethod: _optStr(j['payment_method']),
      totalPaid: toRupees(_int(j['paid_paise'])),
    );

KitchenOrderTicket kotFromApi(Map<String, dynamic> j) => KitchenOrderTicket(
      id: _str(j['id']),
      kotNumber: _str(j['kot_number']),
      orderId: _str(j['order_id']),
      tableNumber: _optStr(j['table_number']),
      orderType: orderTypeFromApi(_str(j['order_type'])),
      waiterName: _str(j['waiter_name'], 'Staff'),
      createdAt: _dtOrNow(j['created_at']),
      status: kotStatusFromApi(_str(j['status'])),
      items: (j['items'] as List? ?? [])
          .whereType<Map>()
          .map((i) => OrderItem(
                id: _str(i['order_item_id']),
                menuItem: _menuItemForLookup(
                  _str(i['order_item_id']),
                  _str(i['name']),
                  0,
                ),
                quantity: _int(i['quantity']),
                isKOTSent: true,
              ))
          .toList(),
      specialInstructions: _optStr(j['note']),
    );

Shift shiftFromApi(Map<String, dynamic> j) => Shift(
      id: _str(j['id']),
      staffId: _str(j['staff_id']),
      staffName: _str(j['staff_name'], 'Staff'),
      startedAt: _dtOrNow(j['started_at']),
      closedAt: _dt(j['closed_at']),
      openingCash: toRupees(_int(j['opening_paise'])),
      openingNotes: _optStr(j['opening_notes']),
      cashSales: toRupees(_int(j['cash_sales_paise'])),
      upiSales: toRupees(_int(j['upi_sales_paise'])),
      cardSales: toRupees(_int(j['card_sales_paise'])),
      refundsCash: toRupees(_int(j['refunds_cash_paise'])),
      refundsDigital: toRupees(_int(j['refunds_digital_paise'])),
      expenses: toRupees(_int(j['expenses_paise'])),
      cashIn: toRupees(_int(j['cash_in_paise'])),
      cashOut: toRupees(_int(j['cash_out_paise'])),
      actualCashClosed: j['counted_paise'] == null
          ? null
          : toRupees(_int(j['counted_paise'])),
      closingNotes: _optStr(j['closing_notes']),
      isClosed: _str(j['status']) == 'closed',
    );

Expense expenseFromApi(Map<String, dynamic> j) => Expense(
      id: _str(j['id']),
      title: _str(j['title']),
      category: expenseCategoryFromApi(_str(j['category'])),
      amount: toRupees(_int(j['amount_paise'])),
      date: _dtOrNow(j['ts']),
      paymentMethod: _str(j['method'], 'Cash'),
      vendor: _optStr(j['vendor']),
      reference: _optStr(j['reference']),
      description: _optStr(j['note']),
    );

Customer customerFromApi(Map<String, dynamic> j) => Customer(
      id: _str(j['id']),
      name: _str(j['name']),
      phone: _str(j['phone']),
      email: _optStr(j['email']),
      address: _optStr(j['address']),
      visits: _int(j['visits']),
      lifetimeSpend: toRupees(_int(j['lifetime_spend_paise'])),
      outstandingCredit: toRupees(_int(j['outstanding_paise'])),
      lastVisit: _dt(j['last_visit']),
    );

InventoryItem inventoryItemFromApi(Map<String, dynamic> j) => InventoryItem(
      id: _str(j['id']),
      name: _str(j['name']),
      availableStock: _double(j['stock']),
      minStock: _double(j['min_stock']),
      unit: _str(j['unit'], 'KG'),
      costPerUnit: toRupees(_int(j['cost_paise'])),
    );

Supplier supplierFromApi(Map<String, dynamic> j) => Supplier(
      id: _str(j['id']),
      name: _str(j['name']),
      mobile: _str(j['mobile']),
      email: _optStr(j['email']),
      category: _str(j['category'], 'General'),
      outstanding: toRupees(_int(j['outstanding_paise'])),
    );

PurchaseRecord purchaseFromApi(Map<String, dynamic> j) => PurchaseRecord(
      id: _str(j['id']),
      invoiceNumber: _str(j['invoice_no']),
      supplierName: _str(j['supplier_name']),
      date: _dtOrNow(j['ts']),
      totalAmount: toRupees(_int(j['total_paise'])),
      paymentStatus: _str(j['status']) == 'pending' ? 'Pending' : 'Paid',
      itemsSummary: _str(j['summary']),
    );

DashboardStats dashboardReportFromApi(Map<String, dynamic> j) => DashboardStats(
      sales: toRupees(_int(j['sales_paise'])),
      orderCount: _int(j['order_count']),
      aov: toRupees(_int(j['aov_paise'])),
      expenses: toRupees(_int(j['expenses_paise'])),
      cashDrawer: toRupees(_int(j['cash_drawer_paise'])),
      pendingKots: _int(j['pending_kots']),
      salesByType: _paiseMapToRupees(j['sales_by_type']),
      salesByTender: _paiseMapToRupees(j['sales_by_tender']),
      topCategories: (j['top_categories'] as List? ?? [])
          .whereType<Map>()
          .map((c) => CategorySales(
                category: _str(c['category']),
                revenue: toRupees(_int(c['revenue_paise'])),
                quantity: _int(c['quantity']),
              ))
          .toList(),
    );

Map<String, double> _paiseMapToRupees(dynamic v) {
  if (v is! Map) return const {};
  return v.map((k, value) => MapEntry(k.toString(), toRupees(_int(v))));
}

List<String> _strList(dynamic v) =>
    (v is List) ? v.map((e) => e.toString()).toList() : const <String>[];

/// Payload helpers for the menu admin editor (variants + modifier groups).
List<Map<String, dynamic>> menuVariantsToApi(List<ProductVariant> variants) =>
    variants
        .map((v) => {'name': v.name, 'price_paise': toPaise(v.price)})
        .toList();

List<Map<String, dynamic>> menuModifierGroupsToApi(List<ModifierGroup> groups) =>
    groups
        .map((g) => {
              'name': g.name,
              'is_multi_select': g.isMultiSelect,
              'is_required': g.isRequired,
              'sort': 0,
              'items': g.items
                  .map((m) => {'name': m.name, 'price_paise': toPaise(m.price)})
                  .toList(),
            })
        .toList();

RestaurantSettings settingsFromApi(Map<String, dynamic> j) {
  final base = RestaurantSettings();
  return base.copyWith(
    restaurantName: _str(j['restaurant_name'], base.restaurantName),
    gstPercentage: _double(j['gst_percent']),
    isGstInclusive: j['is_gst_inclusive'] == true,
    defaultServiceChargePercent: _double(j['service_percent']),
    defaultPackagingCharge: toRupees(_int(j['packaging_paise'])),
    defaultDeliveryCharge: toRupees(_int(j['delivery_paise'])),
    autoPrintKOT: j['auto_print_kot'] != false,
    allowReprint: j['allow_reprint'] != false,
    billingPrinter: _str(j['billing_printer']),
    kitchenPrinter: _str(j['kitchen_printer']),
    barPrinter: _str(j['bar_printer']),
    sections: _strList(j['sections']),
    upiId: _str(j['upi_id']),
    upiName: _str(j['upi_name']),
    upiQrImage: _str(j['upi_qr_image']),
  );
}

Map<String, dynamic> settingsToApi(RestaurantSettings s) => {
      'restaurant_name': s.restaurantName,
      'gst_percent': s.gstPercentage,
      'is_gst_inclusive': s.isGstInclusive,
      'service_percent': s.defaultServiceChargePercent,
      'packaging_paise': toPaise(s.defaultPackagingCharge),
      'delivery_paise': toPaise(s.defaultDeliveryCharge),
      'auto_print_kot': s.autoPrintKOT,
      'allow_reprint': s.allowReprint,
      'billing_printer': s.billingPrinter,
      'kitchen_printer': s.kitchenPrinter,
      'bar_printer': s.barPrinter,
      'sections': s.sections,
      'upi_id': s.upiId,
      'upi_name': s.upiName,
      'upi_qr_image': s.upiQrImage,
    };

Map<String, dynamic>? denominationsToApi(CashDenomination? d) {
  if (d == null) return null;
  return {
    'd500': d.count500,
    'd200': d.count200,
    'd100': d.count100,
    'd50': d.count50,
    'd20': d.count20,
    'd10': d.count10,
  };
}

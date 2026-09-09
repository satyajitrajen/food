import 'menu_model.dart';

enum OrderType { dineIn, takeaway, delivery }
enum OrderStatus { received, preparing, ready, served, billing, completed, cancelled }

enum PaymentMethod { cash, upi, card }

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.card:
        return 'Card';
    }
  }

  static PaymentMethod fromLabel(String? s) {
    switch (s) {
      case 'Cash':
        return PaymentMethod.cash;
      case 'UPI':
        return PaymentMethod.upi;
      case 'Card':
        return PaymentMethod.card;
      default:
        return PaymentMethod.cash;
    }
  }
}

/// Rounds to 2 decimal places (single place for money rounding in Dart).
double roundMoney(double v) => (v * 100).roundToDouble() / 100;

class OrderItem {
  final String id;
  final MenuItem menuItem;
  ProductVariant? selectedVariant;
  List<ModifierItem> selectedModifiers;
  int quantity;
  String? itemNote;
  bool isKOTSent;
  bool isCancelled;
  String? cancelReason;

  OrderItem({
    required this.id,
    required this.menuItem,
    this.selectedVariant,
    this.selectedModifiers = const [],
    this.quantity = 1,
    this.itemNote,
    this.isKOTSent = false,
    this.isCancelled = false,
    this.cancelReason,
  });

  double get unitPrice {
    double base = selectedVariant != null ? selectedVariant!.price : menuItem.price;
    double mods = selectedModifiers
        .where((m) => m.isSelected)
        .fold(0.0, (sum, m) => sum + m.price);
    return roundMoney(base + mods);
  }

  double get totalPrice => unitPrice * quantity;

  String get displayName {
    if (selectedVariant != null) {
      return '${menuItem.name} (${selectedVariant!.name})';
    }
    return menuItem.name;
  }

  OrderItem copy({String? newId}) => OrderItem(
        id: newId ?? id,
        menuItem: menuItem.copy(),
        selectedVariant: selectedVariant?.copy(),
        selectedModifiers: selectedModifiers.map((m) => m.copy()).toList(),
        quantity: quantity,
        itemNote: itemNote,
        isKOTSent: isKOTSent,
        isCancelled: isCancelled,
        cancelReason: cancelReason,
      );
}

class RestaurantOrder {
  final String id;
  final String orderNumber; // e.g. 'ORD-1045'
  final OrderType orderType;
  String? tableId;
  String? tableNumber;
  final DateTime createdAt;
  OrderStatus status;
  String? customerName;
  String? customerPhone;
  String? deliveryAddress;
  String? deliveryNotes;
  String? waiterName;
  int guestCount;
  String? orderNote;
  List<OrderItem> items;

    // Billing adjustments
    double discountPercent;
    double discountAmount;
    String? discountReason;
    double taxPercent; // e.g. 5.0%
    bool isTaxInclusive;
    double serviceCharge;
    double packagingCharge;
    double deliveryCharge;

  // Payment
  String? invoiceNumber;
  DateTime? paidAt;
  String? paymentMethod;
  double totalPaid;

  RestaurantOrder({
    required this.id,
    required this.orderNumber,
    required this.orderType,
    this.tableId,
    this.tableNumber,
    required this.createdAt,
    this.status = OrderStatus.received,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.deliveryNotes,
    this.waiterName,
    this.guestCount = 1,
    this.orderNote,
    required this.items,
    this.discountPercent = 0.0,
    this.discountAmount = 0.0,
    this.discountReason,
    this.taxPercent = 5.0,
    this.isTaxInclusive = false,
    this.serviceCharge = 0.0,
    this.packagingCharge = 0.0,
    this.deliveryCharge = 0.0,
    this.invoiceNumber,
    this.paidAt,
    this.paymentMethod,
    this.totalPaid = 0.0,
  });

  List<OrderItem> get activeItems =>
      items.where((item) => !item.isCancelled).toList();

  List<OrderItem> get cancelledItems =>
      items.where((item) => item.isCancelled).toList();

  int get totalItemCount =>
      activeItems.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      activeItems.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get computedDiscount {
    final double raw;
    if (discountPercent > 0) {
      raw = (subtotal * discountPercent.clamp(0.0, 100.0)) / 100.0;
    } else {
      raw = discountAmount;
    }
    return roundMoney(raw.clamp(0.0, subtotal));
  }

  double get netTaxable => roundMoney((subtotal - computedDiscount).clamp(0.0, double.infinity));

  /// GST base is the net amount plus service charge (service charge attracts
  /// GST under Indian restaurant convention).
  /// Inclusive pricing (FR-O3): the menu price already contains GST, so the
  /// tax is EXTRACTED (base·pct/(100+pct)) instead of added on top.
  double get computedTax => isTaxInclusive
      ? roundMoney(((netTaxable + serviceCharge) * taxPercent) / (100.0 + taxPercent))
      : roundMoney(((netTaxable + serviceCharge) * taxPercent) / 100.0);

  double get cgst => roundMoney(computedTax / 2.0);
  double get sgst => roundMoney(computedTax / 2.0);

  double get totalAdditionalCharges =>
      roundMoney(serviceCharge + packagingCharge + deliveryCharge);

  double get grandTotal => roundMoney(isTaxInclusive
      ? netTaxable + totalAdditionalCharges
      : netTaxable + computedTax + totalAdditionalCharges);

  String get orderTypeLabel {
    switch (orderType) {
      case OrderType.dineIn:
        return 'Dine-In';
      case OrderType.takeaway:
        return 'Takeaway';
      case OrderType.delivery:
        return 'Delivery';
    }
  }

  String get statusLabel {
    switch (status) {
      case OrderStatus.received:
        return 'Received';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.served:
        return 'Served';
      case OrderStatus.billing:
        return 'Billing';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool get isClosed =>
      status == OrderStatus.completed || status == OrderStatus.cancelled;

  /// Deep copy — safe to snapshot for history/persistence.
  RestaurantOrder copy() => RestaurantOrder(
        id: id,
        orderNumber: orderNumber,
        orderType: orderType,
        tableId: tableId,
        tableNumber: tableNumber,
        createdAt: createdAt,
        status: status,
        customerName: customerName,
        customerPhone: customerPhone,
        deliveryAddress: deliveryAddress,
        deliveryNotes: deliveryNotes,
        waiterName: waiterName,
        guestCount: guestCount,
        orderNote: orderNote,
        items: items.map((i) => i.copy()).toList(),
        discountPercent: discountPercent,
        discountAmount: discountAmount,
        discountReason: discountReason,
        taxPercent: taxPercent,
        isTaxInclusive: isTaxInclusive,
        serviceCharge: serviceCharge,
        packagingCharge: packagingCharge,
        deliveryCharge: deliveryCharge,
        invoiceNumber: invoiceNumber,
        paidAt: paidAt,
        paymentMethod: paymentMethod,
        totalPaid: totalPaid,
      );
}

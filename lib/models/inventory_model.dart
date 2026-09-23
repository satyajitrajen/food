class InventoryItem {
  final String id;
  final String name;
  double availableStock;
  final double minStock;
  final String unit; // 'KG', 'Litre', 'Pcs'
  final double costPerUnit;
  // Purchase provenance (W5): where the current stock came from.
  final String? batchNo;
  final String? rackNo;
  final DateTime? purchasedAt;

  InventoryItem({
    required this.id,
    required this.name,
    required this.availableStock,
    required this.minStock,
    required this.unit,
    required this.costPerUnit,
    this.batchNo,
    this.rackNo,
    this.purchasedAt,
  });

  bool get isLowStock => availableStock <= minStock;
}

/// Audit entry for every stock change (wastage, purchase, correction).
class StockAdjustment {
  final String itemId;
  final String itemName;
  final double change; // +purchase / -wastage
  final String reason;
  final String staffName;
  final DateTime timestamp;

  StockAdjustment({
    required this.itemId,
    required this.itemName,
    required this.change,
    required this.reason,
    required this.staffName,
    required this.timestamp,
  });
}

class Supplier {
  final String id;
  final String name;
  final String mobile;
  final String? email;
  final String category;
  double outstanding;
  DateTime? lastPurchase;

  Supplier({
    required this.id,
    required this.name,
    required this.mobile,
    this.email,
    required this.category,
    this.outstanding = 0.0,
    this.lastPurchase,
  });
}

/// Payment recorded against a supplier's outstanding due (W5).
class SupplierPayment {
  final String id;
  final String supplierId;
  final String supplierName;
  final double amount;
  final String method; // Cash / UPI / Card / Bank Transfer
  final DateTime paidAt;
  final String? reference;
  final String staffName;

  SupplierPayment({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.amount,
    required this.method,
    required this.paidAt,
    this.reference,
    required this.staffName,
  });
}

class PurchaseRecord {
  final String id;
  final String invoiceNumber;
  final String supplierName;
  final DateTime date;
  final double totalAmount;
  final String paymentStatus; // 'Paid', 'Pending'
  final String itemsSummary;

  PurchaseRecord({
    required this.id,
    required this.invoiceNumber,
    required this.supplierName,
    required this.date,
    required this.totalAmount,
    required this.paymentStatus,
    required this.itemsSummary,
  });
}

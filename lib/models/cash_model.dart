enum CashFlowType { cashIn, cashOut }

class CashTransaction {
  final String id;
  final CashFlowType type;
  final double amount;
  final String reason;
  final String? reference;
  final DateTime timestamp;
  final String staffName;

  CashTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.reason,
    this.reference,
    required this.timestamp,
    required this.staffName,
  });

  String get typeLabel => type == CashFlowType.cashIn ? 'Cash In' : 'Cash Out';
}

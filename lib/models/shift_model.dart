class CashDenomination {
  final int count500;
  final int count200;
  final int count100;
  final int count50;
  final int count20;
  final int count10;

  CashDenomination({
    this.count500 = 0,
    this.count200 = 0,
    this.count100 = 0,
    this.count50 = 0,
    this.count20 = 0,
    this.count10 = 0,
  });

  double get total =>
      (count500 * 500 +
          count200 * 200 +
          count100 * 100 +
          count50 * 50 +
          count20 * 20 +
          count10 * 10)
          .toDouble();

  CashDenomination copyWith({
    int? count500,
    int? count200,
    int? count100,
    int? count50,
    int? count20,
    int? count10,
  }) {
    return CashDenomination(
      count500: count500 ?? this.count500,
      count200: count200 ?? this.count200,
      count100: count100 ?? this.count100,
      count50: count50 ?? this.count50,
      count20: count20 ?? this.count20,
      count10: count10 ?? this.count10,
    );
  }
}

class Shift {
  final String id;
  final String staffId;
  final String staffName;
  final DateTime startedAt;
  DateTime? closedAt;
  final double openingCash;
  final String? openingNotes;
  double cashSales;
  double upiSales;
  double cardSales;
  double refundsCash;
  double refundsDigital;
  double expenses;
  double cashIn;
  double cashOut;
  double? actualCashClosed;
  String? closingNotes;
  CashDenomination? closingDenominations;
  bool isClosed;

  Shift({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.startedAt,
    this.closedAt,
    required this.openingCash,
    this.openingNotes,
    this.cashSales = 0.0,
    this.upiSales = 0.0,
    this.cardSales = 0.0,
    this.refundsCash = 0.0,
    this.refundsDigital = 0.0,
    this.expenses = 0.0,
    this.cashIn = 0.0,
    this.cashOut = 0.0,
    this.actualCashClosed,
    this.closingNotes,
    this.closingDenominations,
    this.isClosed = false,
  });

  double get totalSales => cashSales + upiSales + cardSales;

  double get refunds => refundsCash + refundsDigital;

  /// Expected physical cash in drawer. Only CASH refunds leave the drawer;
  /// digital refunds do not.
  double get expectedCash =>
      openingCash + cashSales + cashIn - expenses - refundsCash - cashOut;

  double? get cashDifference =>
      actualCashClosed == null ? null : actualCashClosed! - expectedCash;

  /// True when the counted amount matches expected cash (within half a rupee).
  bool isBalanced(double countedCash) =>
      (countedCash - expectedCash).abs() < 0.005;
}

/// Subscription payloads for the POS app's Settings subscription card.
/// Money stays in paise ints here; `dto.dart` converts to rupees at the edge.

class SubscriptionStatus {
  final String planCode;
  final String planName;

  /// trial | active | past_due | suspended | expired | cancelled
  final String status;

  /// '' | created | authenticated | active | pending | halted | cancelled | completed
  final String gatewayStatus;
  final DateTime? periodEnd;
  final double priceRupees;

  SubscriptionStatus({
    required this.planCode,
    required this.planName,
    required this.status,
    required this.gatewayStatus,
    required this.periodEnd,
    required this.priceRupees,
  });

  /// A live (or being-authenticated) gateway mandate owns billing.
  bool get autoRenewLive =>
      gatewayStatus == 'active' ||
      gatewayStatus == 'authenticated' ||
      gatewayStatus == 'pending' ||
      gatewayStatus == 'halted';
}

class RazorpaySubscriptionStart {
  final String subscriptionId;
  final String keyId;
  final String planCode;
  final String planName;
  final int amountPaise;
  final String currency;
  final int registrationPaise;

  RazorpaySubscriptionStart({
    required this.subscriptionId,
    required this.keyId,
    required this.planCode,
    required this.planName,
    required this.amountPaise,
    required this.currency,
    required this.registrationPaise,
  });
}

class RazorpayManualOrder {
  final String orderId;
  final String keyId;
  final int amountPaise;
  final String currency;
  final String planName;

  RazorpayManualOrder({
    required this.orderId,
    required this.keyId,
    required this.amountPaise,
    required this.currency,
    required this.planName,
  });
}

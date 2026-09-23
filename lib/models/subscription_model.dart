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

  /// Free-trial countdown (server truth). Non-zero only when status == trial.
  final DateTime? trialEndsAt;
  final int trialDaysLeft;
  final DateTime? firstChargeAt;

  SubscriptionStatus({
    required this.planCode,
    required this.planName,
    required this.status,
    required this.gatewayStatus,
    required this.periodEnd,
    required this.priceRupees,
    this.trialEndsAt,
    this.trialDaysLeft = 0,
    this.firstChargeAt,
  });

  bool get isTrial => status == 'trial';
  bool get trialAutoPayArmed => isTrial && autoRenewLive;

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

  /// True when the mandate is authorized during the free trial with the
  /// first charge scheduled at trial end (Razorpay start_at).
  final bool trial;
  final DateTime? trialEndsAt;
  final DateTime? firstChargeAt;

  RazorpaySubscriptionStart({
    required this.subscriptionId,
    required this.keyId,
    required this.planCode,
    required this.planName,
    required this.amountPaise,
    required this.currency,
    this.trial = false,
    this.trialEndsAt,
    this.firstChargeAt,
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

/// Result of self-service organization registration
/// (POST /api/v1/auth/register). The admin PIN is server-generated and shown
/// once — the terminal binds immediately so PIN login works right away.
class RegisterOrgResult {
  final String orgCode;
  final String orgId;
  final String orgName;
  final String adminPin;
  final DateTime? trialEndsAt;

  RegisterOrgResult({
    required this.orgCode,
    required this.orgId,
    required this.orgName,
    required this.adminPin,
    this.trialEndsAt,
  });
}

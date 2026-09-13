import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

class CheckoutResult {
  final bool success;
  final String? error;
  final String? wallet;

  const CheckoutResult({required this.success, this.error, this.wallet});
}

/// Thin wrapper over razorpay_flutter: opens native checkout and converts the
/// event stream into a single Future. Server webhooks own subscription state —
/// this result is UI feedback only, never a source of truth.
class RazorpayCheckout {
  final Razorpay _rzp = Razorpay();

  Future<CheckoutResult> open(Map<String, dynamic> options) {
    final completer = Completer<CheckoutResult>();

    void done(CheckoutResult result) {
      _rzp.clear();
      if (!completer.isCompleted) completer.complete(result);
    }

    void onSuccess(PaymentSuccessResponse _) =>
        done(const CheckoutResult(success: true));
    void onFailure(PaymentFailureResponse e) =>
        done(CheckoutResult(success: false, error: e.message ?? 'Payment failed'));
    void onWallet(ExternalWalletResponse w) =>
        done(CheckoutResult(success: false, wallet: w.walletName));

    _rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, onSuccess);
    _rzp.on(Razorpay.EVENT_PAYMENT_ERROR, onFailure);
    _rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, onWallet);
    _rzp.open(options);
    return completer.future;
  }

  void dispose() => _rzp.clear();
}

Map<String, dynamic> subscriptionCheckoutOptions({
  required String keyId,
  required String subscriptionId,
  required String planName,
  String? email,
}) =>
    {
      'key': keyId,
      'subscription_id': subscriptionId,
      'name': 'FoodPOS',
      'description': planName,
      'theme': {'color': '#E2572B'},
      if (email != null && email.isNotEmpty) 'prefill': {'email': email},
    };

Map<String, dynamic> orderCheckoutOptions({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String currency,
  required String description,
}) =>
    {
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': currency,
      'name': 'FoodPOS',
      'description': description,
      'theme': {'color': '#E2572B'},
    };

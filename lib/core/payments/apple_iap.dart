import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

/// The auto-renewable App Store product that buys the Pro plan for a year.
/// Must match FOODPOS_APPLE_PRODUCT_ID on the server.
const appleProProductId = 'com.nexory.hishobkr.pro.yearly';

/// Apple's subscription management page (cancel / change plan).
const appleManageSubscriptionsUrl = 'https://apps.apple.com/account/subscriptions';

/// Apple's standard licence agreement, linked next to the purchase button
/// as App Review requires for auto-renewable subscriptions.
const appleStandardEulaUrl =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

class AppleIapResult {
  /// StoreKit 2 signed transactions (JWS) to post to the server.
  final List<String> signedTransactions;
  final String? error;
  final bool cancelled;

  const AppleIapResult(
      {this.signedTransactions = const [], this.error, this.cancelled = false});
}

/// Thin wrapper over in_app_purchase (StoreKit 2): loads the Pro product,
/// buys or restores it, and returns Apple's signed transactions. The server
/// verifies those and owns subscription state; this is never the source of
/// truth. Not safe for concurrent calls; the subscription card's busy flag
/// serializes them.
class AppleIap {
  // StoreKit 2 is the plugin default (iOS 15+, our minimum): purchase
  // serverVerificationData is the transaction's signed JWS.
  final InAppPurchase _iap = InAppPurchase.instance;

  Future<ProductDetails?> loadProduct() async {
    if (!await _iap.isAvailable()) return null;
    final res = await _iap.queryProductDetails({appleProProductId});
    if (res.productDetails.isEmpty) return null;
    return res.productDetails.first;
  }

  Future<AppleIapResult> buy(ProductDetails product) =>
      _run(() => _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product)),
          restoring: false);

  Future<AppleIapResult> restore() =>
      _run(() async {
        await _iap.restorePurchases();
        return true;
      }, restoring: true);

  /// Starts [start] and collects purchase updates for our product until the
  /// purchase settles. A restore may deliver several (or no) transactions,
  /// so it settles after a short quiet period instead.
  Future<AppleIapResult> _run(Future<bool> Function() start,
      {required bool restoring}) async {
    final signed = <String>[];
    final completer = Completer<AppleIapResult>();
    Timer? quiet;

    void finish(AppleIapResult r) {
      quiet?.cancel();
      if (!completer.isCompleted) completer.complete(r);
    }

    void armQuiet() {
      quiet?.cancel();
      quiet = Timer(const Duration(seconds: 4),
          () => finish(AppleIapResult(signedTransactions: List.of(signed))));
    }

    final sub = _iap.purchaseStream.listen((updates) async {
      for (final p in updates) {
        if (p.productID != appleProProductId) continue;
        switch (p.status) {
          case PurchaseStatus.pending:
            break;
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            signed.add(p.verificationData.serverVerificationData);
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
            if (!restoring) {
              finish(AppleIapResult(signedTransactions: List.of(signed)));
            }
          case PurchaseStatus.error:
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
            finish(AppleIapResult(
                error: p.error?.message ?? 'Purchase failed'));
          case PurchaseStatus.canceled:
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
            finish(const AppleIapResult(cancelled: true));
        }
      }
      if (restoring) armQuiet();
    }, onError: (Object e) => finish(AppleIapResult(error: '$e')));

    try {
      final started = await start();
      if (!started) finish(const AppleIapResult(error: 'Could not start the purchase'));
      if (restoring) armQuiet();
      return await completer.future;
    } catch (e) {
      finish(AppleIapResult(error: '$e'));
      return completer.future;
    } finally {
      await sub.cancel();
    }
  }
}

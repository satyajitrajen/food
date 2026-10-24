import 'package:flutter/foundation.dart';

/// App Store guideline 3.1.1: the iOS build must not sell or prompt for the
/// subscription outside Apple's in-app purchase, so every Razorpay billing
/// action and "pay/renew" call to action is hidden there. Status stays
/// visible.
bool get inAppBillingAllowed =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;

/// iOS sells the same plan through Apple in-app purchase instead.
bool get appleBillingEnabled =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Whether this build offers any way to pay (Razorpay or Apple).
bool get anyBillingAllowed => inAppBillingAllowed || appleBillingEnabled;

import 'package:flutter/foundation.dart';

/// App Store guideline 3.1.1: the iOS build must not sell or prompt for the
/// subscription outside Apple's in-app purchase, so every billing action and
/// "pay/renew" call to action is hidden there. Status stays visible.
bool get inAppBillingAllowed =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;

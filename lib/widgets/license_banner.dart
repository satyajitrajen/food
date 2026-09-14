import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../providers/pos_provider.dart';

/// App-level subscription banner: shown above every screen while the terminal
/// has no active entitlement (trial expired / suspended). New-order entry is
/// blocked by the UI + server; queued data is never dropped.
class LicenseBanner extends StatelessWidget {
  final Widget child;

  const LicenseBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    // The subscription banner should ONLY be shown when:
    // 1. API mode is enabled.
    // 2. An organization is bound and initial terminal setup is complete.
    // 3. A staff member is authenticated/working in the POS.
    // 4. An entitlement has actually been loaded and is inactive/expired/suspended.
    final show = provider.apiEnabled &&
        provider.orgCode != null &&
        !provider.needsOrgSetup &&
        provider.currentStaff != null &&
        provider.entitlement != null &&
        !provider.licenseActive;
    if (!show) return child;

    final entitle = provider.entitlement!;
    final status = entitle.status;
    final message = status == 'suspended'
        ? 'Subscription suspended by the platform.'
        : 'Subscription $status. Renew to keep taking orders.';

    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Material(
              color: AppColors.saffronAmber,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    if (provider.licenseTokenVerified)
                      const Tooltip(
                        message: 'License verified',
                        child: Icon(Icons.verified_user_outlined, color: Colors.white, size: 18),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

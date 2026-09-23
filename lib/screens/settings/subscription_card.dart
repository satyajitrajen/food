import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/payments/razorpay_checkout.dart';
import '../../core/theme/app_theme.dart';
import '../../models/subscription_model.dart';
import '../../providers/pos_provider.dart';

/// Subscription rows + actions inside the Settings "Subscription" section
/// chrome (admins only; the parent gates visibility). Billing actions
/// re-authenticate the org owner one-shot; server webhooks own subscription
/// state — client payment results only trigger a refresh.
class SubscriptionCardBody extends StatefulWidget {
  const SubscriptionCardBody({super.key});

  @override
  State<SubscriptionCardBody> createState() => _SubscriptionCardBodyState();
}

class _SubscriptionCardBodyState extends State<SubscriptionCardBody>
    with WidgetsBindingObserver {
  final _checkout = RazorpayCheckout();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PosProvider>().loadSubscriptionStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkout.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      context.read<PosProvider>().loadSubscriptionStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final status = provider.subscriptionStatus;
    final error = provider.subscriptionStatusError;

    if (status == null) {
      if (error != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(error,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: SizedBox(
            height: 18, width: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final periodText = status.periodEnd == null
        ? '—'
        : DateFormat('dd MMM yyyy').format(status.periodEnd!.toLocal());
    final trialEndText = status.trialEndsAt == null
        ? null
        : DateFormat('dd MMM yyyy').format(status.trialEndsAt!.toLocal());
    final firstChargeText = status.firstChargeAt == null
        ? trialEndText
        : DateFormat('dd MMM yyyy').format(status.firstChargeAt!.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status.isTrial) _trialBanner(status, trialEndText, firstChargeText),
        _row('Plan', status.planName),
        _row('Status', _statusLabel(status.status)),
        _row('Auto-renew', status.autoRenewLive ? 'On' : 'Off'),
        if (status.isTrial && trialEndText != null)
          _row('Trial ends', '$trialEndText (${status.trialDaysLeft}d left)')
        else
          _row('Next cycle', periodText),
        if (status.isTrial && firstChargeText != null && status.autoRenewLive)
          _row('First charge', firstChargeText),
        _row('Price (excl. GST)', '₹${status.priceRupees.toStringAsFixed(0)}'),
        const SizedBox(height: 8),
        _actions(provider, status),
      ],
    );
  }

  Widget _trialBanner(
      SubscriptionStatus status, String? trialEndText, String? firstChargeText) {
    final days = status.trialDaysLeft;
    final message = status.autoRenewLive
        ? 'Free trial${days > 0 ? ' — $days day${days == 1 ? '' : 's'} left' : ''}'
            '${firstChargeText != null ? ', first charge $firstChargeText' : ''}. Auto-pay is on.'
        : 'Free trial${days > 0 ? ' — $days day${days == 1 ? '' : 's'} left' : ''}'
            '${trialEndText != null ? ' (ends $trialEndText)' : ''}. Enable auto-pay now — first charge happens automatically.';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryGreenLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.schedule_outlined,
              size: 18, color: AppColors.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 12, height: 1.4, color: AppColors.textDark)),
          ),
        ],
      ),
    );
  }

  Widget _actions(PosProvider provider, SubscriptionStatus status) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
            height: 18, width: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (status.autoRenewLive) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => _cancelAutoRenew(provider),
          child: const Text('Cancel auto-renew'),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: () => _payOneCycle(provider),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Pay one cycle now'),
          ),
          FilledButton(
            onPressed: () => _enableAutoRenew(provider),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(status.isTrial
                ? 'Enable auto-pay'
                : 'Enable auto-renew'),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'trial':
        return 'Trial';
      case 'active':
        return 'Active';
      case 'past_due':
        return 'Past due';
      case 'suspended':
        return 'Suspended';
      case 'expired':
        return 'Expired';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s.isEmpty ? '—' : s;
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textDark)),
          ),
        ],
      ),
    );
  }

  /// One-shot owner sign-in dialog. Returns (token, email) or null.
  Future<(String, String)?> _askOwnerToken() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String? error;
    return showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Owner sign-in'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Billing actions need the organization owner account.',
                  style: TextStyle(fontSize: 12)),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Owner email'),
              ),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final provider = context.read<PosProvider>();
                final token = await provider.loginOwnerForAction(
                    emailCtrl.text.trim(), passCtrl.text);
                if (!dialogContext.mounted) return;
                if (token == null) {
                  setDialogState(() => error =
                      provider.subscriptionActionError ??
                          'Invalid owner email or password');
                  return;
                }
                Navigator.pop(
                    dialogContext, (token, emailCtrl.text.trim()));
              },
              child: const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enableAutoRenew(PosProvider provider) async {
    final creds = await _askOwnerToken();
    if (creds == null || !mounted) return;
    final (token, email) = creds;
    setState(() => _busy = true);
    try {
      final start = await provider.startAutoRenew(token);
      if (!mounted) return;
      if (start == null) {
        _snack(context, provider.subscriptionActionError ?? 'Could not start auto-renew');
        return;
      }
      final result = await _checkout.open(subscriptionCheckoutOptions(
        keyId: start.keyId,
        subscriptionId: start.subscriptionId,
        planName: start.planName,
        email: email,
      ));
      if (!mounted) return;
      if (result.wallet != null) {
        _snack(context, 'Payment handed off to ${result.wallet}');
      } else if (!result.success) {
        _snack(context, result.error ?? 'Payment cancelled');
      } else if (start.trial && start.firstChargeAt != null) {
        _snack(context,
            'Auto-pay authorized — first charge on ${DateFormat('dd MMM yyyy').format(start.firstChargeAt!.toLocal())}');
      } else {
        _snack(context, 'Payment received — status updating');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await provider.loadSubscriptionStatus();
    }
  }

  Future<void> _payOneCycle(PosProvider provider) async {
    final creds = await _askOwnerToken();
    if (creds == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final order = await provider.createManualRenewal(creds.$1);
      if (!mounted) return;
      if (order == null) {
        _snack(context, provider.subscriptionActionError ?? 'Could not create the order');
        return;
      }
      final result = await _checkout.open(orderCheckoutOptions(
        keyId: order.keyId,
        orderId: order.orderId,
        amountPaise: order.amountPaise,
        currency: order.currency,
        description: 'One cycle — ${order.planName}',
      ));
      if (!mounted) return;
      if (result.wallet != null) {
        _snack(context, 'Payment handed off to ${result.wallet}');
      } else if (!result.success) {
        _snack(context, result.error ?? 'Payment cancelled');
      } else {
        _snack(context, 'Payment received — status updating');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await provider.loadSubscriptionStatus();
    }
  }

  Future<void> _cancelAutoRenew(PosProvider provider) async {
    final creds = await _askOwnerToken();
    if (creds == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final ok = await provider.cancelAutoRenew(creds.$1);
      if (!mounted) return;
      _snack(context, ok
          ? 'Auto-renew will stop at the end of this cycle'
          : provider.subscriptionActionError ?? 'Could not cancel auto-renew');
    } finally {
      if (mounted) setState(() => _busy = false);
      await provider.loadSubscriptionStatus();
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/app_nav.dart';
import '../models/kot_model.dart';
import '../providers/pos_provider.dart';
import '../screens/running_orders/running_order_detail_screen.dart';

/// App-level navigator key — lets the ready-alert overlay push routes from
/// above the Navigator (MaterialApp.builder context).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Shows a top banner on the assigned waiter's terminal the moment a KOT of
/// theirs is marked Ready by the kitchen (any screen, above pushed routes),
/// with a sound + unread count. In-app only — no OS push.
class ReadyKotAlerter extends StatefulWidget {
  final Widget child;

  const ReadyKotAlerter({super.key, required this.child});

  @override
  State<ReadyKotAlerter> createState() => _ReadyKotAlerterState();
}

class _ReadyKotAlerterState extends State<ReadyKotAlerter> {
  int _lastTick = 0;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final alerts = provider.readyAlerts;
    final tick = provider.readyAlertTick;

    if (tick != _lastTick && alerts.isNotEmpty) {
      _lastTick = tick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.mediumImpact();
      });
    }

    return Stack(
      children: [
        widget.child,
        if (alerts.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white,
                  child: _ReadyBanner(alerts: alerts, provider: provider),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReadyBanner extends StatelessWidget {
  final List<KitchenOrderTicket> alerts;
  final PosProvider provider;

  const _ReadyBanner({required this.alerts, required this.provider});

  void _view(BuildContext context, KitchenOrderTicket kot) {
    final order =
        provider.orders.where((o) => o.id == kot.orderId).firstOrNull;
    if (order != null) {
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => RunningOrderDetailScreen(order: order)),
      );
    } else {
      provider.goToDest(AppDest.tables);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kot = alerts.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.vegGreenBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle, color: AppColors.vegGreen, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order Ready — serve now!',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${kot.kotNumber} · ${kot.tableNumber != null ? 'Table ${kot.tableNumber}' : kot.orderType.name.toUpperCase()} · ${kot.totalQuantity} items',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (alerts.length > 1)
                Text('+${alerts.length - 1}',
                    style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  provider.acknowledgeReadyKot(kot.id);
                },
                child: const Text('Dismiss'),
              ),
              const SizedBox(width: 6),
              if (alerts.length > 1)
                TextButton(
                  onPressed: provider.dismissAllReadyAlerts,
                  child: const Text('Dismiss all'),
                ),
              FilledButton.icon(
                onPressed: () => _view(context, kot),
                icon: const Icon(Icons.restaurant, size: 16),
                label: const Text('View Order'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

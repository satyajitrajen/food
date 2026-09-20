import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/models/subscription_model.dart';
import 'package:food_pos/providers/pos_provider.dart';
import 'package:food_pos/screens/settings/subscription_card.dart';
import 'package:provider/provider.dart';

/// Demo-mode provider (apiEnabled=false keeps network paths inert) with the
/// subscription getters overridden to inject card states.
class _FakePosProvider extends PosProvider {
  SubscriptionStatus? status;
  String? statusError;

  @override
  SubscriptionStatus? get subscriptionStatus => status;

  @override
  String? get subscriptionStatusError => statusError;

  @override
  Future<void> loadSubscriptionStatus() async {}

  void emitChange() => notifyListeners();
}

SubscriptionStatus _status(
    {String subStatus = 'trial', String gatewayStatus = ''}) {
  final trial = subStatus == 'trial';
  return SubscriptionStatus(
    planCode: 'pro',
    planName: 'Pro',
    status: subStatus,
    gatewayStatus: gatewayStatus,
    periodEnd: trial ? null : DateTime(2026, 9, 20),
    priceRupees: 1999,
    trialEndsAt: trial ? DateTime(2026, 9, 27) : null,
    trialDaysLeft: trial ? 7 : 0,
    firstChargeAt: trial ? DateTime(2026, 9, 27) : null,
  );
}

Widget _wrap(PosProvider provider) =>
    ChangeNotifierProvider<PosProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: ListView(children: const [SubscriptionCardBody()]),
        ),
      ),
    );

void main() {
  testWidgets('shows plan, status and both payment actions when auto-renew is off',
      (tester) async {
    final provider = _FakePosProvider()..status = _status();
    await tester.pumpWidget(_wrap(provider));

    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Trial'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    // Trial CTA authorizes the mandate with the first charge at trial end.
    expect(find.text('Enable auto-pay'), findsOneWidget);
    expect(find.text('Pay one cycle now'), findsOneWidget);
    expect(find.text('Cancel auto-renew'), findsNothing);
    // Trial banner + countdown rows.
    expect(find.textContaining('Free trial'), findsOneWidget);
    expect(find.text('Trial ends'), findsOneWidget);
  });

  testWidgets('shows cancel only when auto-renew is live', (tester) async {
    final provider = _FakePosProvider()
      ..status = _status(subStatus: 'active', gatewayStatus: 'active');
    await tester.pumpWidget(_wrap(provider));

    expect(find.text('On'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Enable auto-renew'), findsNothing);
    expect(find.text('Enable auto-pay'), findsNothing);
    expect(find.text('Pay one cycle now'), findsNothing);
    expect(find.text('Cancel auto-renew'), findsOneWidget);
  });

  testWidgets('trial with auto-pay armed shows first charge and cancel',
      (tester) async {
    final provider = _FakePosProvider()
      ..status = _status(subStatus: 'trial', gatewayStatus: 'active');
    await tester.pumpWidget(_wrap(provider));

    expect(find.text('On'), findsOneWidget);
    expect(find.text('First charge'), findsOneWidget);
    expect(find.text('Cancel auto-renew'), findsOneWidget);
    expect(find.text('Enable auto-pay'), findsNothing);
  });

  testWidgets('shows the load error when no status is available',
      (tester) async {
    final provider = _FakePosProvider()..statusError = 'No subscription on file';
    await tester.pumpWidget(_wrap(provider));

    expect(find.text('No subscription on file'), findsOneWidget);
    expect(find.text('Enable auto-renew'), findsNothing);
  });

  testWidgets('rebuilds when the provider notifies (webhook-driven refresh)',
      (tester) async {
    final provider = _FakePosProvider()..status = _status();
    await tester.pumpWidget(_wrap(provider));
    expect(find.text('Off'), findsOneWidget);

    provider.status = _status(subStatus: 'active', gatewayStatus: 'active');
    provider.emitChange();
    await tester.pump();

    expect(find.text('On'), findsOneWidget);
    expect(find.text('Cancel auto-renew'), findsOneWidget);
  });
}

// Preview pages that need first-run state, a backend, or printer hardware.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:food_pos/core/theme/app_theme.dart';
import 'package:food_pos/providers/pos_provider.dart';
import 'package:food_pos/screens/auth/org_registration_screen.dart';
import 'package:food_pos/screens/auth/org_setup_screen.dart';
import 'package:food_pos/screens/auth/select_outlet_screen.dart';
import 'package:food_pos/screens/auth/splash_screen.dart';
import 'package:food_pos/screens/modals/printer_error_dialog.dart';
import 'package:food_pos/screens/settings/subscription_card.dart';
import 'demo_main.dart' show createDemoProvider;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider<PosProvider>.value(
    value: createDemoProvider(),
    child: MaterialApp(debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme, home: const ExtraDemoPages()),
  ));
}

class ExtraDemoPages extends StatelessWidget {
  const ExtraDemoPages({super.key});

  @override
  Widget build(BuildContext context) {
    final pages = <String, Widget>{
      'Organization setup': const OrgSetupScreen(),
      'Organization registration': const OrgRegistrationScreen(),
      'Outlet selection': const SelectOutletScreen(),
      'Splash': const SplashScreen(),
      'Subscription (backend required)': Scaffold(
        appBar: AppBar(title: const Text('Subscription')),
        body: const Padding(padding: EdgeInsets.all(20), child: SubscriptionCardBody()),
      ),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Additional demo pages')),
      body: ListView(children: [
        const Padding(padding: EdgeInsets.all(16), child: Text(
          'Isolated preview: setup and subscription require a test backend; '
          'printer recovery requires real hardware. No API calls are enabled.')),
        for (final page in pages.entries)
          ListTile(title: Text(page.key), trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page.value))),
        ListTile(title: const Text('Printer error dialog (preview)'),
          onTap: () => PrinterErrorDialog.show(context, printerName: 'Demo printer')),
      ]),
    );
  }
}

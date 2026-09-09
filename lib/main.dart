import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/pos_provider.dart';
import 'screens/auth/splash_screen.dart';
import 'widgets/license_banner.dart';
import 'widgets/ready_kot_alerter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
  runApp(const RestoPosApp());
}

class RestoPosApp extends StatelessWidget {
  const RestoPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PosProvider(apiEnabled: true)),
      ],
      child: MaterialApp(
        title: 'Resto POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        navigatorKey: appNavigatorKey,
        // Draws the license banner + in-app "Order ready" alert above routes.
        builder: (context, child) => LicenseBanner(
          child: ReadyKotAlerter(child: child ?? const SizedBox.shrink()),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

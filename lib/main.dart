import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'providers/pos_provider.dart';
import 'screens/auth/splash_screen.dart';
import 'widgets/license_banner.dart';
import 'widgets/ready_kot_alerter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await PushNotificationService.instance.initialize();
  } catch (e) {
    debugPrint('Firebase init note: $e');
  }
  // Draw edge-to-edge on all Android versions (Android 15+ enforces it for
  // targetSdk 35): transparent system bars + no contrast scrim, so layout
  // insets are deterministic and every screen must honor them explicitly
  // (see BottomInsets). Relying on the system nav color alone leaves
  // bottom-docked bars sliding under the opaque nav bar on some devices.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
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
        title: 'Hishobkr',
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

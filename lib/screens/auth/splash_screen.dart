import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/staff_model.dart';
import '../../providers/pos_provider.dart';
import 'org_setup_screen.dart';
import 'pin_login_screen.dart';
import '../kitchen/kitchen_board_screen.dart';
import '../shell/main_adaptive_shell.dart';
import '../shift/open_shift_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
    _route();
  }

  /// Waits for boot (tenant/session restore) while keeping the brand visible
  /// briefly, then lands where the state dictates: org setup for unbound
  /// terminals, straight to the role home for still-signed-in staff
  /// (login persists until explicit logout), else PIN login.
  Future<void> _route() async {
    final provider = context.read<PosProvider>();
    await Future.wait([
      provider.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () {},
      ),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);
    if (!mounted) return;
    Widget next;
    if (provider.needsOrgSetup) {
      next = const OrgSetupScreen();
    } else if (provider.currentStaff != null) {
      provider.goToHome();
      final role = provider.currentStaff?.role;
      if (role == StaffRole.kitchen) {
        next = const KitchenBoardScreen(showLock: true);
      } else if (role == StaffRole.waiter || provider.currentShift != null) {
        next = const MainAdaptiveShell();
      } else {
        next = const OpenShiftScreen();
      }
    } else {
      next = const PinLoginScreen();
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => next),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Brand Logo
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Image.asset(
                  'assets/logo.png',
                  width: 280,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                provider.tenantOrgName != null
                    ? '${provider.tenantOrgName} · ${provider.currentOutlet.name}'
                    : '${provider.currentOutlet.name} · Counter ${provider.currentOutlet.terminal}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 48),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.vegGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Syncing local catalog & offline state...',
                    style: TextStyle(
                      color: AppColors.textLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

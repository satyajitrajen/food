import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import 'org_setup_screen.dart';
import 'pin_login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();

    // Navigate after 1.8s: SaaS terminals first bind their org code.
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        final provider = context.read<PosProvider>();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => provider.needsOrgSetup
                ? const OrgSetupScreen()
                : const PinLoginScreen(),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
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
              // Logo Icon
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryOrange, Color(0xFFFF922B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryOrange.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.restaurant_menu_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'RESTO POS',
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${provider.currentOutlet.name} · Terminal ${provider.currentOutlet.terminal}',
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

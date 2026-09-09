import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/staff_model.dart';
import '../../widgets/numeric_keypad.dart';
import 'select_outlet_screen.dart';
import 'org_setup_screen.dart';
import '../shift/open_shift_screen.dart';
import '../shell/main_adaptive_shell.dart';
import '../kitchen/kitchen_board_screen.dart';

class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  Staff? _selectedStaff;
  String _pin = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final provider = context.read<PosProvider>();
    _selectedStaff = provider.staffList.isEmpty ? null : provider.staffList.first;
  }

  bool _verifying = false;

  void _onKeyPress(String digit) {
    if (_verifying) return;
    if (_pin.length < 4) {
      setState(() {
        _pin += digit;
        _errorMessage = null;
      });

      if (_pin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _errorMessage = null;
      });
    }
  }

  void _onClear() {
    setState(() {
      _pin = '';
      _errorMessage = null;
    });
  }

  Future<void> _verifyPin() async {
    if (_verifying || _selectedStaff == null) return;
    setState(() => _verifying = true);
    final provider = context.read<PosProvider>();
    // Login by the selected profile id — the provider handles server-first
    // auth with a local PIN fallback for offline terminals.
    final ok = await provider.loginStaffById(_selectedStaff!.id, _pin);
    if (!mounted) return;
    if (ok) {
      // Land each role on its home screen. Kitchen goes straight to the
      // full-screen KOT board; waiters never open shifts (cashier/manager/
      // admin do when no shift is active yet).
      provider.goToHome();
      final role = provider.currentStaff?.role;
      if (role == StaffRole.kitchen) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const KitchenBoardScreen(showLock: true)),
        );
      } else if (role == StaffRole.waiter || provider.currentShift != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainAdaptiveShell()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const OpenShiftScreen()),
        );
      }
    } else {
      setState(() {
        _errorMessage = 'Incorrect PIN for ${_selectedStaff?.name}. Try again.';
        _pin = '';
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    // Keep the selected profile valid across server hydration.
    if (!provider.staffList.any((s) => s.id == _selectedStaff?.id)) {
      _selectedStaff = provider.staffList.isEmpty ? null : provider.staffList.first;
    }

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Outlet and Terminal Banner
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SelectOutletScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.creamSubtle,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.storefront_outlined, size: 16, color: AppColors.primaryOrange),
                          const SizedBox(width: 8),
                          Text(
                            '${provider.currentOutlet.name} (${provider.currentOutlet.terminal})',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Staff Avatar & Profile
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.primaryOrangeLight,
                    backgroundImage: NetworkImage(_selectedStaff?.avatarUrl ?? ''),
                    onBackgroundImageError: (_, _) {},
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selectedStaff?.name ?? 'Staff Login',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryOrangeLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _selectedStaff?.roleTitle ?? '',
                      style: const TextStyle(
                        color: AppColors.primaryOrange,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // PIN Indicator Dots
                  if (_verifying) ...[
                    const SizedBox(height: 6),
                    const CircularProgressIndicator(
                      color: AppColors.primaryOrange,
                      strokeWidth: 2.5,
                    ),
                    const SizedBox(height: 6),
                  ] else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final isFilled = index < _pin.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: isFilled ? AppColors.primaryOrange : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isFilled ? AppColors.primaryOrange : AppColors.borderMedium,
                              width: 1.5,
                            ),
                          ),
                        );
                      }),
                    ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.nonVegRed, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Keypad
                  NumericKeypad(
                    onKeyPressed: _onKeyPress,
                    onDelete: _onDelete,
                    onClear: _onClear,
                  ),
                  const SizedBox(height: 20),
                  // Switch Staff List
                  const Text('Switch Profile:', style: TextStyle(color: AppColors.textLight, fontSize: 12)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: provider.staffList.map((s) {
                        final isSelected = _selectedStaff?.id == s.id;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedStaff = s;
                                _pin = '';
                                _errorMessage = null;
                              });
                            },
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? AppColors.primaryOrange : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppColors.primaryOrangeLight,
                                    backgroundImage: NetworkImage(s.avatarUrl),
                                    onBackgroundImageError: (_, _) {},
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  s.name.split(' ').first,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? AppColors.primaryOrange : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                if (provider.apiEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextButton.icon(
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('Change organization code'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const OrgSetupScreen(rebind: true)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

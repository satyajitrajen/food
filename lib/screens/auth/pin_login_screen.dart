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
  final TextEditingController _pickerSearchC = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<PosProvider>();
    _selectedStaff = provider.currentOutletStaff.isEmpty ? null : provider.currentOutletStaff.first;
  }

  @override
  void dispose() {
    _pickerSearchC.dispose();
    super.dispose();
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

  void _selectStaff(Staff s) {
    setState(() {
      _selectedStaff = s;
      _pin = '';
      _errorMessage = null;
    });
  }

  /// Staff picker: searchable, vertically scrolling list in a bottom sheet.
  /// Full names + roles stay readable no matter how large the team gets.
  /// Fixed-height sheet with an internally scrolling list (no nested-scroll
  /// coordination surprises on small screens).
  void _showStaffPicker(List<Staff> outletStaff) {
    _pickerSearchC.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final q = _pickerSearchC.text.trim().toLowerCase();
          final filtered = q.isEmpty
              ? outletStaff
              : outletStaff
                  .where((s) =>
                      s.name.toLowerCase().contains(q) ||
                      s.roleTitle.toLowerCase().contains(q))
                  .toList();
          final sheetHeight =
              MediaQuery.of(sheetContext).size.height * 0.75;
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
            child: SizedBox(
              height: sheetHeight,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderMedium,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Who is signing in?',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                            ),
                          ),
                          Text(
                            '${filtered.length} of ${outletStaff.length}',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        controller: _pickerSearchC,
                        autofocus: outletStaff.length > 6,
                        decoration: InputDecoration(
                          hintText: 'Search name or role…',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _pickerSearchC.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _pickerSearchC.clear();
                                    setSheetState(() {});
                                  },
                                ),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No staff match that search.',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => const Divider(
                                  height: 1,
                                  indent: 68,
                                  color: AppColors.borderLight),
                              itemBuilder: (_, i) {
                                final s = filtered[i];
                                final isSelected =
                                    _selectedStaff?.id == s.id;
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 22,
                                    backgroundColor:
                                        AppColors.primaryGreenLight,
                                    backgroundImage:
                                        NetworkImage(s.avatarUrl),
                                    onBackgroundImageError: (error, stackTrace) {},
                                    child: s.avatarUrl.isEmpty
                                        ? Text(
                                            s.name.isEmpty
                                                ? '?'
                                                : s.name[0].toUpperCase(),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.primaryGreen),
                                          )
                                        : null,
                                  ),
                                  title: Text(
                                    s.name,
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Text(
                                    s.roleTitle,
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(Icons.check_circle,
                                          color: AppColors.primaryGreen)
                                      : const Icon(
                                          Icons.chevron_right,
                                          color: AppColors.textLight),
                                  selected: isSelected,
                                  selectedTileColor:
                                      AppColors.primaryGreenLight,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  onTap: () {
                                    _selectStaff(s);
                                    Navigator.of(sheetContext).pop();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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
    final outletStaff = provider.currentOutletStaff;
    // Keep the selected profile valid across server hydration and outlet switches.
    if (!outletStaff.any((s) => s.id == _selectedStaff?.id)) {
      _selectedStaff = outletStaff.isEmpty ? null : outletStaff.first;
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
                  // Brand mark
                  Image.asset(
                    'assets/logo.png',
                    width: 76,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 10),
                  // Outlet and Counter Banner
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
                          const Icon(Icons.storefront_outlined, size: 16, color: AppColors.primaryGreen),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${provider.currentOutlet.name} · Counter ${provider.currentOutlet.terminal}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Staff Avatar & Profile (tappable: opens the picker)
                  InkWell(
                    onTap: _verifying || outletStaff.isEmpty
                        ? null
                        : () => _showStaffPicker(outletStaff),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: AppColors.primaryGreenLight,
                            backgroundImage: NetworkImage(_selectedStaff?.avatarUrl ?? ''),
                            onBackgroundImageError: (error, stackTrace) {},
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _selectedStaff?.name ?? 'Staff Login',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (outletStaff.length > 1) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.switch_account_outlined,
                                    size: 16, color: AppColors.textMuted),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreenLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _selectedStaff?.roleTitle ?? '',
                      style: const TextStyle(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Switch profile: a searchable sheet that scales from a
                  // handful of staff to dozens (the old horizontal avatar
                  // strip broke down and fought the page scroll). Placed
                  // above the keypad so it never sits below the fold.
                  if (outletStaff.isNotEmpty)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.switch_account_outlined, size: 18),
                      label: Text(
                        outletStaff.length == 1
                            ? '1 profile on this counter'
                            : 'Switch profile · ${outletStaff.length} on this counter',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _verifying ? null : () => _showStaffPicker(outletStaff),
                    ),
                  const SizedBox(height: 14),
                  // PIN Indicator Dots
                  if (_verifying) ...[
                    const SizedBox(height: 6),
                    const CircularProgressIndicator(
                      color: AppColors.primaryGreen,
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
                            color: isFilled ? AppColors.primaryGreen : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isFilled ? AppColors.primaryGreen : AppColors.borderMedium,
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
                  const SizedBox(height: 16),
                  // Keypad
                  NumericKeypad(
                    onKeyPressed: _onKeyPress,
                    onDelete: _onDelete,
                    onClear: _onClear,
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

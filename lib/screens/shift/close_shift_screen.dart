import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/shift_model.dart';
import '../auth/pin_login_screen.dart';

class CloseShiftScreen extends StatefulWidget {
  const CloseShiftScreen({super.key});

  @override
  State<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends State<CloseShiftScreen> {
  final TextEditingController _actualCashController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // Denominations — start from zero; the operator counts the drawer.
  int _c500 = 0;
  int _c200 = 0;
  int _c100 = 0;
  int _c50 = 0;
  bool _touchedDenoms = false;

  double get _computedPhysicalCash =>
      (_c500 * 500 + _c200 * 200 + _c100 * 100 + _c50 * 50).toDouble();

  @override
  void initState() {
    super.initState();
    final provider = context.read<PosProvider>();
    _actualCashController.text =
        (provider.currentShift?.expectedCash ?? 0.0).toStringAsFixed(0);
  }

  void _updateActualCashFromDenom() {
    _touchedDenoms = true;
    setState(() {
      _actualCashController.text = _computedPhysicalCash.toStringAsFixed(0);
    });
  }

  @override
  void dispose() {
    _actualCashController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Widget _buildDenomRow(int value, int count, Function(int) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('₹$value Note', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: count > 0 ? () => onChanged(count - 1) : null,
              ),
              SizedBox(
                width: 36,
                child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.primaryOrange),
                onPressed: () => onChanged(count + 1),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '= ₹${value * count}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final shift = provider.currentShift;

    if (shift == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Close Shift & Z-Report', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No active shift'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final expectedCash = shift.expectedCash;
    // An empty field means "not counted" — never silently assume it matches.
    final counted = _touchedDenoms || _actualCashController.text.trim().isNotEmpty
        ? double.tryParse(_actualCashController.text)
        : null;
    final actualCash = counted ?? expectedCash;
    final discrepancy = actualCash - expectedCash;
    final isCounted = counted != null;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Close Shift & Z-Report', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Expected Cash vs Actual Cash Comparison Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Expected Cash in Drawer', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              SizedBox(height: 2),
                            ],
                          ),
                          Text(
                            '₹${expectedCash.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                          ),
                        ],
                      ),
                      const Divider(height: 24, color: AppColors.borderLight),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Actual Physical Cash Counted', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              SizedBox(height: 2),
                            ],
                          ),
                          Text(
                            '₹${actualCash.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              color: AppColors.primaryOrange,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24, color: AppColors.borderLight),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Drawer Discrepancy:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: !isCounted
                                  ? AppColors.creamSubtle
                                  : shift.isBalanced(actualCash)
                                      ? AppColors.vegGreenBg
                                      : (discrepancy > 0 ? AppColors.infoBlueBg : AppColors.nonVegRedBg),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              !isCounted
                                  ? 'Cash not counted'
                                  : shift.isBalanced(actualCash)
                                      ? 'Exact Match (₹0)'
                                      : (discrepancy > 0 ? '+₹${discrepancy.toStringAsFixed(0)} (Surplus)' : '−₹${(-discrepancy).toStringAsFixed(0)} (Shortage)'),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: !isCounted
                                    ? AppColors.textMuted
                                    : shift.isBalanced(actualCash)
                                        ? AppColors.vegGreen
                                        : (discrepancy > 0 ? AppColors.infoBlue : AppColors.nonVegRed),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Physical Denominations Counter
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Count Cash Denominations', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          Text(
                            'Total: ₹${_computedPhysicalCash.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryOrange),
                          ),
                        ],
                      ),
                      const Divider(color: AppColors.borderLight, height: 16),
                      _buildDenomRow(500, _c500, (v) {
                        _c500 = v;
                        _updateActualCashFromDenom();
                      }),
                      _buildDenomRow(200, _c200, (v) {
                        _c200 = v;
                        _updateActualCashFromDenom();
                      }),
                      _buildDenomRow(100, _c100, (v) {
                        _c100 = v;
                        _updateActualCashFromDenom();
                      }),
                      _buildDenomRow(50, _c50, (v) {
                        _c50 = v;
                        _updateActualCashFromDenom();
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Shift Closing Notes / Discrepancy Reason',
                    prefixIcon: Icon(Icons.note_alt_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                    onPressed: () {
                      provider.closeShift(
                        actualCash: actualCash,
                        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
                        denominations: CashDenomination(
                          count500: _c500,
                          count200: _c200,
                          count100: _c100,
                          count50: _c50,
                        ),
                      );

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => AlertDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.print, color: AppColors.primaryOrange),
                              SizedBox(width: 8),
                              Text('Shift Closed & Z-Report', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                            ],
                          ),
                          content: SizedBox(
                            width: 520,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}'),
                                  Text('Staff: ${shift.staffName}'),
                                  const Divider(),
                                  Text('Total Sales: ₹${shift.totalSales.toStringAsFixed(0)}'),
                                  Text('Cash Sales: ₹${shift.cashSales.toStringAsFixed(0)}'),
                                  Text('UPI Sales: ₹${shift.upiSales.toStringAsFixed(0)}'),
                                  Text('Card Sales: ₹${shift.cardSales.toStringAsFixed(0)}'),
                                  Text('Expenses: ₹${shift.expenses.toStringAsFixed(0)}'),
                                  Text('Expected Cash: ₹${expectedCash.toStringAsFixed(0)}'),
                                  Text('Actual Cash: ₹${actualCash.toStringAsFixed(0)}'),
                                  Text('Difference: ₹${discrepancy.toStringAsFixed(0)}'),
                                  const Divider(),
                                  // W8 (FR-R3): server-computed Z-report, when the
                                  // terminal is online — the cross-terminal truth.
                                  FutureBuilder<Map<String, dynamic>?>(
                                    future: provider.fetchZReport(shift.id),
                                    builder: (context, snap) {
                                      if (snap.connectionState != ConnectionState.done) {
                                        return const Text('Server Z-Report: checking…',
                                            style: TextStyle(color: AppColors.textMuted, fontSize: 12));
                                      }
                                      final z = snap.data;
                                      if (z == null) {
                                        return const Text('Server Z-Report unavailable (offline) — local figures above.',
                                            style: TextStyle(color: AppColors.textMuted, fontSize: 12));
                                      }
                                      final expectedS = ((z['expected_cash_paise'] as num?)?.toDouble() ?? 0) / 100.0;
                                      final countedS = ((z['counted_cash_paise'] as num?)?.toDouble() ?? 0) / 100.0;
                                      final diffS = ((z['difference_paise'] as num?)?.toDouble() ?? 0) / 100.0;
                                      final totalS = ((z['total_sales_paise'] as num?)?.toDouble() ?? 0) / 100.0;
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('— Server Z-Report —',
                                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.infoBlue)),
                                          Text('Total Sales: ₹${totalS.toStringAsFixed(0)}'),
                                          Text('Expected Cash: ₹${expectedS.toStringAsFixed(0)}'),
                                          Text('Counted Cash: ₹${countedS.toStringAsFixed(0)}'),
                                          Text('Variance: ₹${diffS.toStringAsFixed(0)}'),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const PinLoginScreen()),
                                  (route) => false,
                                );
                              },
                              child: const Text('Back to Login'),
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const PinLoginScreen()),
                                  (route) => false,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('✓ Z-Report sent to thermal printer!')),
                                );
                              },
                              icon: const Icon(Icons.print, size: 16),
                              label: const Text('Print Z-Report'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.lock, size: 20),
                    label: const Text('Confirm Shift Closure', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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

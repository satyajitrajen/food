import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../models/shift_model.dart';
import '../../providers/pos_provider.dart';
import '../auth/pin_login_screen.dart';

/// End-of-shift cash count. The count is blind: the expected drawer amount is
/// only revealed after the cashier commits a count, so the count can't be
/// "adjusted" to match.
class CloseShiftScreen extends StatefulWidget {
  const CloseShiftScreen({super.key});

  @override
  State<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends State<CloseShiftScreen> {
  static const _notes = [500, 200, 100, 50, 20, 10];
  final Map<int, int> _counts = {for (final n in _notes) n: 0};
  final TextEditingController _coinsController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _closing = false;

  double get _coins => double.tryParse(_coinsController.text.trim()) ?? 0;

  double get _counted =>
      _counts.entries.fold<double>(0, (s, e) => s + e.key * e.value) + _coins;

  CashDenomination get _denominations => CashDenomination(
        count500: _counts[500]!,
        count200: _counts[200]!,
        count100: _counts[100]!,
        count50: _counts[50]!,
        count20: _counts[20]!,
        count10: _counts[10]!,
        coins: _coins,
      );

  @override
  void dispose() {
    _coinsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit(PosProvider provider, Shift shift) async {
    final counted = _counted;
    final expected = shift.expectedCash;
    final diff = counted - expected;
    final balanced = shift.isBalanced(counted);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close shift?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _line('You counted', formatInr(counted)),
            _line('Expected in drawer', formatInr(expected)),
            const Divider(),
            _line(
              balanced ? 'Balanced' : (diff > 0 ? 'Excess' : 'Short'),
              balanced ? formatInr(0) : formatInr(diff.abs()),
              color: balanced
                  ? AppColors.success
                  : (diff > 0 ? AppColors.infoBlue : AppColors.danger),
            ),
            if (!balanced && _notesController.text.trim().isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Add a note explaining the difference before closing.',
                    style: TextStyle(color: AppColors.danger, fontSize: 12)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Recount')),
          FilledButton(
            onPressed: !balanced && _notesController.text.trim().isEmpty
                ? null
                : () => Navigator.of(ctx).pop(true),
            child: const Text('Close shift'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _closing = true);
    await provider.closeShift(
      actualCash: counted,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      denominations: _denominations,
    );
    final server = await provider.fetchZReport(shift.id);
    if (!mounted) return;
    setState(() => _closing = false);
    await _showZReport(provider, shift, server);
  }

  Future<void> _showZReport(PosProvider provider, Shift shift, Map<String, dynamic>? server) async {
    double paise(String k) => ((server?[k] as num?)?.toDouble() ?? 0) / 100.0;
    final expected = server != null ? paise('expected_cash_paise') : shift.expectedCash;
    final counted = server != null ? paise('counted_cash_paise') : (shift.actualCashClosed ?? 0);
    final totalSales = server != null ? paise('total_sales_paise') : shift.totalSales;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Shift closed'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _line('Staff', shift.staffName),
                _line('Opened', formatDateTime(shift.startedAt)),
                _line('Closed', formatDateTime(shift.closedAt ?? DateTime.now())),
                const Divider(),
                _line('Total sales', formatInr(totalSales)),
                _line('Cash', formatInr(shift.cashSales)),
                _line('UPI', formatInr(shift.upiSales)),
                _line('Card', formatInr(shift.cardSales)),
                _line('Refunds', formatInr(shift.refundsCash + shift.refundsDigital)),
                _line('Cash expenses', formatInr(shift.expenses)),
                const Divider(),
                _line('Expected cash', formatInr(expected)),
                _line('Counted cash', formatInr(counted)),
                _line('Difference', formatInr(counted - expected),
                    color: (counted - expected).abs() < 0.01 ? AppColors.success : AppColors.danger),
                if (server == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Offline: these are this terminal\'s figures. The server Z-report '
                      'will be available once the shift close syncs.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok = await provider.printZReport(shift, server: server);
              messenger.showSnackBar(SnackBar(
                content: Text(ok ? 'Z-report sent to the printer' : (provider.printerError ?? 'Print failed')),
                backgroundColor: ok ? AppColors.success : AppColors.danger,
              ));
            },
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Print Z-report'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // The drawer is closed: sign the cashier out of this terminal.
              provider.logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const PinLoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Done & sign out'),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );

  Widget _denomRow(int value) {
    final count = _counts[value]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text('₹$value', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: 'One less ₹$value',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: count > 0 ? () => setState(() => _counts[value] = count - 1) : null,
          ),
          SizedBox(
            width: 56,
            child: TextField(
              key: ValueKey('denom-$value-$count'),
              controller: TextEditingController(text: '$count'),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
              onSubmitted: (v) => setState(() => _counts[value] = int.tryParse(v)?.clamp(0, 9999) ?? 0),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
          IconButton(
            tooltip: 'One more ₹$value',
            icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryGreen),
            onPressed: () => setState(() => _counts[value] = count + 1),
          ),
          Expanded(
            child: Text(
              formatInr(value * count),
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600),
            ),
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
        appBar: AppBar(title: const Text('Close shift')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('No shift is open on this terminal.'),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Close shift')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Count the cash in the drawer. The expected amount is shown after you submit.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.creamCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    children: [
                      for (final n in _notes) _denomRow(n),
                      const Divider(),
                      Row(
                        children: [
                          const SizedBox(width: 64, child: Text('Coins', style: TextStyle(fontWeight: FontWeight.w800))),
                          Expanded(
                            child: TextField(
                              controller: _coinsController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                isDense: true,
                                prefixText: '₹ ',
                                hintText: 'Total of coins & small notes',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Counted cash', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ),
                          Text(
                            formatInr(_counted),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.primaryGreen),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Closing notes (required if the drawer is short or over)',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _closing ? null : () => _submit(provider, shift),
                    icon: _closing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.lock_outline),
                    label: const Text('Submit count', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

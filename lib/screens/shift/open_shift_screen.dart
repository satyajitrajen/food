import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/shift_model.dart';
import '../shell/main_adaptive_shell.dart';

class OpenShiftScreen extends StatefulWidget {
  const OpenShiftScreen({super.key});

  @override
  State<OpenShiftScreen> createState() => _OpenShiftScreenState();
}

class _OpenShiftScreenState extends State<OpenShiftScreen> {
  final TextEditingController _cashController = TextEditingController(text: '5000');
  final TextEditingController _notesController = TextEditingController();

  // Denominations counters
  int _c500 = 6;
  int _c200 = 5;
  int _c100 = 8;
  int _c50 = 4;

  double get _computedTotal => (_c500 * 500 + _c200 * 200 + _c100 * 100 + _c50 * 50).toDouble();

  @override
  void initState() {
    super.initState();
    _cashController.text = _computedTotal.toStringAsFixed(0);
  }

  /// Denomination taps adjust the typed total by the delta instead of
  /// clobbering a manually edited amount.
  void _applyDenomDelta(double delta) {
    final current = double.tryParse(_cashController.text) ?? 0.0;
    final next = (current + delta).clamp(0.0, double.infinity);
    setState(() {
      _cashController.text = next.toStringAsFixed(0);
    });
  }

  @override
  void dispose() {
    _cashController.dispose();
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
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
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

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Open Daily Shift', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Shift Staff Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primaryOrangeLight,
                        backgroundImage: NetworkImage(provider.currentStaff?.avatarUrl ?? ''),
                        onBackgroundImageError: (_, _) {},
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.currentStaff?.name ?? 'Staff',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          Text(
                            '${provider.currentStaff?.roleTitle ?? ""} · ${provider.currentOutlet.name}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Opening Drawer Float Cash:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _cashController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primaryOrange),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.currency_rupee, color: AppColors.primaryOrange),
                    labelText: 'Opening Cash (₹)',
                  ),
                ),
                const SizedBox(height: 20),
                // Denomination Breakup
                Container(
                  padding: const EdgeInsets.all(16),
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
                          const Text('Cash Denominations', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          Text(
                            'Total: ₹${_computedTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryOrange),
                          ),
                        ],
                      ),
                      const Divider(color: AppColors.borderLight, height: 16),
                      _buildDenomRow(500, _c500, (v) {
                        _applyDenomDelta((v - _c500) * 500.0);
                        _c500 = v;
                      }),
                      _buildDenomRow(200, _c200, (v) {
                        _applyDenomDelta((v - _c200) * 200.0);
                        _c200 = v;
                      }),
                      _buildDenomRow(100, _c100, (v) {
                        _applyDenomDelta((v - _c100) * 100.0);
                        _c100 = v;
                      }),
                      _buildDenomRow(50, _c50, (v) {
                        _applyDenomDelta((v - _c50) * 50.0);
                        _c50 = v;
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Shift Notes (e.g. Clean float from morning change)',
                    prefixIcon: Icon(Icons.notes, size: 18),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      final cash = double.tryParse(_cashController.text) ?? _computedTotal;
                      provider.openShift(
                        openingCash: cash,
                        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
                        denominations: CashDenomination(
                          count500: _c500,
                          count200: _c200,
                          count100: _c100,
                          count50: _c50,
                        ),
                      );
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const MainAdaptiveShell()),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✓ Shift Opened with ₹${cash.toStringAsFixed(0)} Opening Float!'),
                          backgroundColor: AppColors.vegGreen,
                        ),
                      );
                    },
                    child: const Text('Start Shift & Open Register →', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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

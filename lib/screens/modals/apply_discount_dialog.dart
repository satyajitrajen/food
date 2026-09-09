import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import 'manager_pin_dialog.dart';

class ApplyDiscountDialog extends StatefulWidget {
  const ApplyDiscountDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const ApplyDiscountDialog(),
    );
  }

  @override
  State<ApplyDiscountDialog> createState() => _ApplyDiscountDialogState();
}

class _ApplyDiscountDialogState extends State<ApplyDiscountDialog> {
  bool _isPercentage = true;
  final TextEditingController _valController = TextEditingController(text: '10');
  String _selectedReason = 'Customer Loyalty';

  final List<String> _reasons = [
    'Customer Loyalty',
    'Promotional Campaign',
    'Manager Courtesy',
    'Staff Discount',
    'Delay in Service',
  ];

  @override
  void dispose() {
    _valController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SizedBox(
          width: 540,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Apply Discount', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Segmented Percentage vs Fixed Amount
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Percentage (%)')),
                      selected: _isPercentage,
                      selectedColor: AppColors.primaryOrange,
                      labelStyle: TextStyle(
                        color: _isPercentage ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => setState(() => _isPercentage = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Fixed Amount (₹)')),
                      selected: !_isPercentage,
                      selectedColor: AppColors.primaryOrange,
                      labelStyle: TextStyle(
                        color: !_isPercentage ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => setState(() => _isPercentage = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _valController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _isPercentage ? 'Discount Percentage (%)' : 'Discount Amount (₹)',
                  prefixIcon: Icon(_isPercentage ? Icons.percent : Icons.currency_rupee, size: 18),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Discount Reason:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _reasons.map((r) {
                  final isSelected = _selectedReason == r;
                  return ChoiceChip(
                    label: Text(r),
                    selected: isSelected,
                    selectedColor: AppColors.primaryOrange,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    onSelected: (_) => setState(() => _selectedReason = r),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        provider.applyDiscount(percent: 0, amount: 0, reason: null);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Remove Discount'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                    onPressed: () async {
                      var val = double.tryParse(_valController.text) ?? 0.0;
                      if (val <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a discount greater than zero'),
                            backgroundColor: AppColors.nonVegRed,
                          ),
                        );
                        return;
                      }
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      // High discounts (> 20% or > 500) require manager pin
                      // — verified server-side too (FR-A3).
                      String? managerPin;
                      if ((_isPercentage && val > 20) || (!_isPercentage && val > 500)) {
                        managerPin = await ManagerPinDialog.show(
                          context,
                          title: 'Manager Approval Required',
                          description: 'Discount above standard limit requires Manager PIN.',
                        );
                        if (managerPin == null) return;
                      }
                      // Clamp to valid range; provider re-clamps against subtotal.
                      if (_isPercentage) {
                        val = val.clamp(0.0, 100.0);
                      } else {
                        val = val.clamp(0.0, provider.activeOrder?.subtotal ?? 0.0);
                        if (val <= 0) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Nothing to discount — the cart is empty'),
                              backgroundColor: AppColors.nonVegRed,
                            ),
                          );
                          return;
                        }
                      }

                      if (_isPercentage) {
                        provider.applyDiscount(percent: val, reason: _selectedReason, managerPin: managerPin);
                      } else {
                        provider.applyDiscount(amount: val, reason: _selectedReason, managerPin: managerPin);
                      }
                      if (!context.mounted) return;
                      navigator.pop();
                    },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
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

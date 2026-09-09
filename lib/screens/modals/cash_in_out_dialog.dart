import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';

class CashInOutDialog extends StatefulWidget {
  final bool isCashIn;

  const CashInOutDialog({super.key, required this.isCashIn});

  static void show(BuildContext context, {required bool isCashIn}) {
    showDialog(
      context: context,
      builder: (ctx) => CashInOutDialog(isCashIn: isCashIn),
    );
  }

  @override
  State<CashInOutDialog> createState() => _CashInOutDialogState();
}

class _CashInOutDialogState extends State<CashInOutDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _refController = TextEditingController();
  String _selectedReason = 'Petty Cash';

  final List<String> _cashInReasons = [
    'Opening Float Top-up',
    'Change Replenishment',
    'Owner Deposit',
    'Other Inflow',
  ];

  final List<String> _cashOutReasons = [
    'Petty Cash Expense',
    'Supplier / Vendor Payout',
    'Bank Deposit',
    'Staff Advance',
    'Emergency Payout',
  ];

  @override
  void initState() {
    super.initState();
    _selectedReason = widget.isCashIn ? _cashInReasons.first : _cashOutReasons.first;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final reasons = widget.isCashIn ? _cashInReasons : _cashOutReasons;

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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: widget.isCashIn ? AppColors.vegGreenBg : AppColors.nonVegRedBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isCashIn ? Icons.arrow_downward : Icons.arrow_upward,
                          color: widget.isCashIn ? AppColors.vegGreen : AppColors.nonVegRed,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.isCashIn ? 'Cash In (Deposit)' : 'Cash Out (Withdrawal)',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Reason:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reasons.map((r) {
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
              const SizedBox(height: 16),
              TextField(
                controller: _refController,
                decoration: const InputDecoration(
                  labelText: 'Reference / Voucher Note (Optional)',
                  prefixIcon: Icon(Icons.tag, size: 18),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isCashIn ? AppColors.vegGreen : AppColors.primaryOrange,
                  ),
                  onPressed: () {
                    final amount = double.tryParse(_amountController.text) ?? 0.0;
                    if (amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter an amount greater than zero'),
                          backgroundColor: AppColors.nonVegRed,
                        ),
                      );
                      return;
                    }
                    // Cash Out cannot exceed what is physically in the drawer.
                    if (!widget.isCashIn && amount > provider.currentShift!.expectedCash + 0.005) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Cash Out exceeds drawer balance (₹${provider.currentShift!.expectedCash.toStringAsFixed(0)})'),
                          backgroundColor: AppColors.nonVegRed,
                        ),
                      );
                      return;
                    }

                    if (widget.isCashIn) {
                      provider.addCashIn(
                        amount: amount,
                        reason: _selectedReason,
                        reference: _refController.text.trim().isNotEmpty ? _refController.text.trim() : null,
                      );
                    } else {
                      provider.addCashOut(
                        amount: amount,
                        reason: _selectedReason,
                        reference: _refController.text.trim().isNotEmpty ? _refController.text.trim() : null,
                      );
                    }
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '✓ Recorded ${widget.isCashIn ? "Cash In" : "Cash Out"} of ₹${amount.toStringAsFixed(0)}',
                        ),
                        backgroundColor: AppColors.vegGreen,
                      ),
                    );
                  },
                  child: Text(
                    widget.isCashIn ? 'Add Cash to Drawer' : 'Remove Cash from Drawer',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
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

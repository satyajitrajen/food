import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../core/format.dart';
import '../../models/order_model.dart';
import 'manager_pin_dialog.dart';

class RefundDialog extends StatefulWidget {
  final RestaurantOrder order;

  const RefundDialog({super.key, required this.order});

  static void show(BuildContext context, RestaurantOrder order) {
    showDialog(
      context: context,
      builder: (ctx) => RefundDialog(order: order),
    );
  }

  @override
  State<RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<RefundDialog> {
  bool _isFullRefund = true;
  bool _saving = false;
  late TextEditingController _amountController;
  String _selectedReason = 'Customer Dissatisfaction';
  /// Bill minus what was already refunded (partial refunds add up).
  double get _refundable =>
      roundMoney((widget.order.grandTotal - widget.order.refundedAmount).clamp(0.0, double.infinity));

  String _refundMode = 'Cash';

  final List<String> _reasons = [
    'Customer Dissatisfaction',
    'Wrong Billing / Overcharged',
    'Food Quality Issue',
    'Order Cancelled After Payment',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: rupeeInput(_refundable));
    // Default to returning money the way it came in.
    _refundMode = 'Original Method';
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<PosProvider>();

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
                  Text(
                    'Refund Invoice ${widget.order.invoiceNumber ?? widget.order.orderNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Full vs Partial Refund Toggle
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Full Refund')),
                      selected: _isFullRefund,
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: _isFullRefund ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _isFullRefund = true;
                          _amountController.text = rupeeInput(_refundable);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Partial Refund')),
                      selected: !_isFullRefund,
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: !_isFullRefund ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) => setState(() => _isFullRefund = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                enabled: !_isFullRefund,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(
                  labelText: 'Refund Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Reason for Refund:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _reasons.map((r) {
                  final isSelected = _selectedReason == r;
                  return ChoiceChip(
                    label: Text(r),
                    selected: isSelected,
                    selectedColor: AppColors.primaryGreen,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    onSelected: (_) => setState(() => _selectedReason = r),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const Text('Refund Mode:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: ['Cash', 'UPI', 'Original Method'].map((m) {
                  final isSelected = _refundMode == m;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(m),
                      selected: isSelected,
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => _refundMode = m),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.nonVegRed),
                  onPressed: _saving ? null : () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    // Refunds are manager-gated on the server too (FR-A3).
                    final managerPin = await ManagerPinDialog.show(
                      context,
                      title: 'Refund Authorization',
                      description: 'Manager approval required to issue a customer refund.',
                    );
                    if (managerPin == null) return;
                    if (!context.mounted) return;

                    final parsed = double.tryParse(_amountController.text.trim()) ?? 0.0;
                    final amount = roundMoney(parsed);
                    if (amount <= 0 || amount > _refundable + 0.005) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Enter an amount up to ${formatInr(_refundable)}'),
                          backgroundColor: AppColors.nonVegRed,
                        ),
                      );
                      return;
                    }
                    setState(() => _saving = true);
                    final error = await provider.processRefund(
                      orderId: widget.order.id,
                      amount: amount,
                      reason: _selectedReason,
                      isFullRefund: _isFullRefund,
                      refundMode: _refundMode,
                      managerPin: managerPin,
                    );
                    if (!context.mounted) return;
                    if (error != null) {
                      setState(() => _saving = false);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Refund not recorded: $error'),
                          backgroundColor: AppColors.nonVegRed,
                        ),
                      );
                      return;
                    }
                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Refund of ${formatInr(amount)} recorded'),
                        backgroundColor: AppColors.vegGreen,
                      ),
                    );
                  },
                  child: Text(_saving ? 'Saving…' : 'Confirm Refund', style: const TextStyle(fontWeight: FontWeight.w700)),
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

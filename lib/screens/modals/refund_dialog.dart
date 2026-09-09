import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
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
  late TextEditingController _amountController;
  String _selectedReason = 'Customer Dissatisfaction';
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
    _amountController = TextEditingController(text: widget.order.grandTotal.toStringAsFixed(0));
    _refundMode = widget.order.paymentMethod ?? 'Cash';
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
                      selectedColor: AppColors.primaryOrange,
                      labelStyle: TextStyle(
                        color: _isFullRefund ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                      onSelected: (_) {
                        setState(() {
                          _isFullRefund = true;
                          _amountController.text = widget.order.grandTotal.toStringAsFixed(0);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Partial Refund')),
                      selected: !_isFullRefund,
                      selectedColor: AppColors.primaryOrange,
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
                      selectedColor: AppColors.primaryOrange,
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
                  onPressed: () async {
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

                    final paid = widget.order.totalPaid > 0
                        ? widget.order.totalPaid
                        : widget.order.grandTotal;
                    final parsed = double.tryParse(_amountController.text) ?? 0.0;
                    final amount = parsed.clamp(0.0, paid);
                    if (amount <= 0) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Enter a valid refund amount'),
                          backgroundColor: AppColors.nonVegRed,
                        ),
                      );
                      return;
                    }
                    final recorded = provider.processRefund(
                      orderId: widget.order.id,
                      amount: amount,
                      reason: _selectedReason,
                      isFullRefund: _isFullRefund,
                      refundMode: _refundMode,
                      managerPin: managerPin,
                    );
                    navigator.pop();
                    if (recorded) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('✓ Refund of ₹${amount.toStringAsFixed(0)} processed successfully'),
                          backgroundColor: AppColors.vegGreen,
                        ),
                      );
                    } else {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Refund could not be recorded (order already refunded/cancelled)'),
                          backgroundColor: AppColors.nonVegRed,
                        ),
                      );
                    }
                  },
                  child: const Text('Confirm Refund', style: TextStyle(fontWeight: FontWeight.w700)),
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

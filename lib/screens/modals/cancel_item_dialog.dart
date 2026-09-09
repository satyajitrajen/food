import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/order_model.dart';
import 'manager_pin_dialog.dart';

class CancelItemDialog extends StatefulWidget {
  final OrderItem item;
  final Function(String reason, String? managerPin) onConfirmCancel;

  const CancelItemDialog({super.key, required this.item, required this.onConfirmCancel});

  static void show(BuildContext context, {required OrderItem item, required Function(String reason, String? managerPin) onConfirmCancel}) {
    showDialog(
      context: context,
      builder: (ctx) => CancelItemDialog(item: item, onConfirmCancel: onConfirmCancel),
    );
  }

  @override
  State<CancelItemDialog> createState() => _CancelItemDialogState();
}

class _CancelItemDialogState extends State<CancelItemDialog> {
  String _selectedReason = 'Customer Cancelled';
  final TextEditingController _customReasonController = TextEditingController();

  final List<String> _reasons = [
    'Wrong Item Ordered',
    'Customer Cancelled',
    'Kitchen Delayed / Out of Stock',
    'Duplicate Item Added',
    'Quality / Taste Complaint',
    'Other',
  ];

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          width: 520,
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                        decoration: const BoxDecoration(
                          color: AppColors.nonVegRedBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.remove_circle_outline, color: AppColors.nonVegRed, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Cancel Item',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Cancel "${widget.item.displayName}" (${widget.item.quantity} × ₹${widget.item.unitPrice.toStringAsFixed(0)}). Cancelled items stay recorded in audit log.',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text('Select Reason for Cancellation:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              for (var r in _reasons)
                InkWell(
                  onTap: () => setState(() => _selectedReason = r),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          _selectedReason == r ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: _selectedReason == r ? AppColors.primaryOrange : AppColors.textLight,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(r, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_selectedReason == 'Other') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customReasonController,
                  decoration: const InputDecoration(hintText: 'Enter specific reason...'),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.nonVegRed),
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        // Manager authorization (FR-A3) — verified against
                        // the server PINs online; the PIN rides along so the
                        // server can enforce its own gate.
                        final managerPin = await ManagerPinDialog.show(
                          context,
                          title: 'Item Void Authorization',
                          description: 'Manager approval required to void item from running order.',
                        );
                        if (managerPin != null) {
                          final reason = _selectedReason == 'Other' && _customReasonController.text.isNotEmpty
                              ? _customReasonController.text.trim()
                              : _selectedReason;
                          widget.onConfirmCancel(reason, managerPin);
                          if (!context.mounted) return;
                          navigator.pop();
                        }
                      },
                      child: const Text('Confirm Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}

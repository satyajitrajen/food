import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/order_model.dart';

class SplitBillDialog extends StatefulWidget {
  final RestaurantOrder order;

  const SplitBillDialog({super.key, required this.order});

  static void show(BuildContext context, RestaurantOrder order) {
    showDialog(
      context: context,
      builder: (ctx) => SplitBillDialog(order: order),
    );
  }

  @override
  State<SplitBillDialog> createState() => _SplitBillDialogState();
}

class _SplitBillDialogState extends State<SplitBillDialog> {
  int _splitModeIndex = 0; // 0: Equal, 1: By Item, 2: Custom Amount
  late int _personCount;
  late double _totalAmount;

  @override
  void initState() {
    super.initState();
    _totalAmount = widget.order.grandTotal;
    _personCount = widget.order.guestCount.clamp(2, 99);
  }

  @override
  Widget build(BuildContext context) {
    // Equal split with remainder handling so shares always sum to the total.
    final base = (_totalAmount / _personCount).floorToDouble();
    final lastShare = _totalAmount - base * (_personCount - 1);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SizedBox(
          width: 560,
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
                  const Text('Split Bill', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.creamSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Bill Amount:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '₹${_totalAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primaryOrange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Tabs: Equal Split | By Item | Custom
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Equal Split')),
                  ButtonSegment(value: 1, label: Text('By Item')),
                  ButtonSegment(value: 2, label: Text('Custom')),
                ],
                selected: {_splitModeIndex},
                onSelectionChanged: (set) => setState(() => _splitModeIndex = set.first),
              ),
              const SizedBox(height: 20),
              if (_splitModeIndex == 0) ...[
                // Equal Split UI
                const Text('Number of People:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: AppColors.primaryOrange),
                      onPressed: _personCount > 2 ? () => setState(() => _personCount--) : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '$_personCount Guests',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryOrange),
                      onPressed: () => setState(() => _personCount++),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrangeLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Text('Each Person Pays:', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        base == lastShare
                            ? '₹${base.toStringAsFixed(0)} × $_personCount'
                            : '₹${base.toStringAsFixed(0)} × ${_personCount - 1} + ₹${lastShare.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primaryOrange,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sums to ₹${_totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ] else if (_splitModeIndex == 1) ...[
                // By Item Split UI
                const Text('Assign Items to Guests:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.order.activeItems.length,
                    itemBuilder: (ctx, idx) {
                      final item = widget.order.activeItems[idx];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        trailing: Text(
                          '₹${item.totalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                // By Item / Custom splits land with split-tender (Phase 3).
                // Show an honest placeholder instead of fabricated numbers.
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.creamSubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 20, color: AppColors.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _splitModeIndex == 1
                              ? 'Item-level guest assignment is coming with split-tender payments.'
                              : 'Custom per-guest amounts are coming with split-tender payments.',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _splitModeIndex == 0
                      ? () {
                          final plan = <double>[
                            for (var i = 0; i < _personCount - 1; i++) base,
                            lastShare,
                          ];
                          Navigator.of(context).pop(plan);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '✓ Bill split $_personCount ways (₹${plan.join(" + ₹")}) — collect at payment.'),
                              backgroundColor: AppColors.vegGreen,
                            ),
                          );
                        }
                      : null,
                  child: const Text('Proceed to Split Payment'),
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

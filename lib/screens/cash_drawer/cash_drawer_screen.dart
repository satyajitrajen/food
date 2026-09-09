import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/cash_model.dart';
import '../modals/cash_in_out_dialog.dart';

class CashDrawerScreen extends StatelessWidget {
  const CashDrawerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final shift = provider.currentShift;

    if (shift == null) {
      return Scaffold(
        backgroundColor: AppColors.creamBg,
        appBar: AppBar(
          title: const Text('Cash Drawer Management', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 44, color: AppColors.textLight),
                const SizedBox(height: 12),
                const Text('No active shift — open a shift to manage the drawer.',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
        ),
      );
    }

    final opening = shift.openingCash;
    final expectedCash = shift.expectedCash;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Cash Drawer Management', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Big Mathematical Balance Card
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EXPECTED CASH IN DRAWER',
                    style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹${expectedCash.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppColors.primaryOrange,
                      fontWeight: FontWeight.w900,
                      fontSize: 38,
                      letterSpacing: -1.0,
                    ),
                  ),
                  const Divider(height: 24, color: AppColors.borderLight),
                  // Breakdown Lines
                  _buildMathRow('Opening Cash Float', '+₹${opening.toStringAsFixed(0)}', AppColors.textDark),
                  _buildMathRow('Cash Sales Received', '+₹${shift.cashSales.toStringAsFixed(0)}', AppColors.vegGreen),
                  _buildMathRow('Cash In (Deposits)', '+₹${shift.cashIn.toStringAsFixed(0)}', AppColors.infoBlue),
                  _buildMathRow('Cash Expenses Paid', '−₹${shift.expenses.toStringAsFixed(0)}', AppColors.nonVegRed),
                  _buildMathRow('Cash Refunds Issued', '−₹${shift.refundsCash.toStringAsFixed(0)}', AppColors.nonVegRed),
                  _buildMathRow('Cash Out (Withdrawals)', '−₹${shift.cashOut.toStringAsFixed(0)}', AppColors.nonVegRed),
                  const Divider(height: 24, color: AppColors.borderLight),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.vegGreen),
                          onPressed: () => CashInOutDialog.show(context, isCashIn: true),
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          label: const Text('Cash In'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.nonVegRed),
                          onPressed: () => CashInOutDialog.show(context, isCashIn: false),
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          label: const Text('Cash Out'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Cash Movements Log
            const Text('Cash In / Out History', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            // Cash movements recorded during the current shift only.
            if (provider.cashTransactions.where((tx) => !tx.timestamp.isBefore(shift.startedAt)).isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: const Center(child: Text('No manual cash transactions logged in this shift.')),
              )
            else
              Builder(builder: (context) {
                final shiftTxs = provider.cashTransactions
                    .where((tx) => !tx.timestamp.isBefore(shift.startedAt))
                    .toList();
                return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: shiftTxs.length,
                itemBuilder: (context, index) {
                  final tx = shiftTxs[index];
                  final isCashIn = tx.type == CashFlowType.cashIn;
                  final timeStr = DateFormat('hh:mm a').format(tx.timestamp);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isCashIn ? AppColors.vegGreenBg : AppColors.nonVegRedBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isCashIn ? Icons.arrow_downward : Icons.arrow_upward,
                            color: isCashIn ? AppColors.vegGreen : AppColors.nonVegRed,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tx.reason, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                              Text(
                                '${tx.staffName} · $timeStr ${tx.reference != null ? "· Ref: ${tx.reference}" : ""}',
                                style: const TextStyle(color: AppColors.textLight, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${isCashIn ? "+" : "−"}₹${tx.amount.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: isCashIn ? AppColors.vegGreen : AppColors.nonVegRed,
                          ),
                        ),
                      ],
                    ),
                  );
                },
                );
              }),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildMathRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: valueColor),
          ),
        ],
      ),
    );
  }
}

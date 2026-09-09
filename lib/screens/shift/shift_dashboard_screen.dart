import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/stat_kpi_card.dart';
import '../modals/cash_in_out_dialog.dart';
import 'close_shift_screen.dart';
import 'open_shift_screen.dart';

class ShiftDashboardScreen extends StatelessWidget {
  const ShiftDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final shift = provider.currentShift;

    if (shift == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shift Management')),
        body: SafeArea(
          top: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.alarm_off, size: 48, color: AppColors.textLight),
                const SizedBox(height: 12),
                const Text('No Active Shift Currently Open', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OpenShiftScreen()),
                    );
                  },
                  child: const Text('Open New Shift'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final startTimeFormatted = DateFormat('hh:mm a, dd MMM').format(shift.startedAt);

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Shift Dashboard', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CloseShiftScreen()),
              );
            },
            icon: const Icon(Icons.lock_clock, color: AppColors.nonVegRed, size: 18),
            label: const Text('Close Shift', style: TextStyle(color: AppColors.nonVegRed, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shift Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.textDark, Color(0xFF34302C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white24,
                    backgroundImage: NetworkImage(provider.currentStaff?.avatarUrl ?? ''),
                    onBackgroundImageError: (_, _) {},
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              shift.staffName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.vegGreen,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'ACTIVE SHIFT',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Started: $startTimeFormatted · Terminal: ${provider.currentOutlet.terminal}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Cash Drawer Live Formula Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Current Expected Cash in Drawer', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                      Icon(Icons.point_of_sale, color: AppColors.primaryOrange, size: 20),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹${shift.expectedCash.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppColors.primaryOrange,
                      fontWeight: FontWeight.w900,
                      fontSize: 32,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Formula: Opening (₹${shift.openingCash.toStringAsFixed(0)}) + Cash Sales (₹${shift.cashSales.toStringAsFixed(0)}) + Cash In (₹${shift.cashIn.toStringAsFixed(0)}) − Expenses (₹${shift.expenses.toStringAsFixed(0)}) − Cash Refunds (₹${shift.refundsCash.toStringAsFixed(0)}) − Cash Out (₹${shift.cashOut.toStringAsFixed(0)})',
                    style: const TextStyle(color: AppColors.textLight, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => CashInOutDialog.show(context, isCashIn: true),
                          icon: const Icon(Icons.arrow_downward, color: AppColors.vegGreen, size: 16),
                          label: const Text('Cash In'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => CashInOutDialog.show(context, isCashIn: false),
                          icon: const Icon(Icons.arrow_upward, color: AppColors.nonVegRed, size: 16),
                          label: const Text('Cash Out'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // KPI Grid
            const Text('Shift Sales & Financials', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                StatKpiCard(
                  title: 'Cash Sales',
                  value: '₹${shift.cashSales.toStringAsFixed(0)}',
                  icon: Icons.payments_outlined,
                  iconColor: AppColors.vegGreen,
                  iconBgColor: AppColors.vegGreenBg,
                ),
                StatKpiCard(
                  title: 'UPI / Digital',
                  value: '₹${shift.upiSales.toStringAsFixed(0)}',
                  icon: Icons.qr_code_2_outlined,
                  iconColor: AppColors.infoBlue,
                  iconBgColor: AppColors.infoBlueBg,
                ),
                StatKpiCard(
                  title: 'Card Sales',
                  value: '₹${shift.cardSales.toStringAsFixed(0)}',
                  icon: Icons.credit_card_outlined,
                  iconColor: AppColors.saffronAmber,
                  iconBgColor: AppColors.saffronAmberBg,
                ),
                StatKpiCard(
                  title: 'Shift Expenses',
                  value: '₹${shift.expenses.toStringAsFixed(0)}',
                  icon: Icons.receipt_long_outlined,
                  iconColor: AppColors.nonVegRed,
                  iconBgColor: AppColors.nonVegRedBg,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
}

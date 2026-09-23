import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/media.dart';
import '../../core/payments/upi_qr.dart';
import '../../core/theme/app_theme.dart';
import '../../models/order_model.dart';
import '../../providers/pos_provider.dart';
import '../receipt/payment_success_screen.dart';
import '../modals/manager_pin_dialog.dart';
import '../../widgets/confirm_dialog.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _selectedPaymentMode = 'Cash'; // 'Cash', 'UPI', 'Card', 'Credit'
  final TextEditingController _cashReceivedController = TextEditingController();
  final TextEditingController _cardRefController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<PosProvider>();
    final total = provider.activeOrder?.grandTotal ?? 0.0;
    _cashReceivedController.text = total.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _cashReceivedController.dispose();
    _cardRefController.dispose();
    super.dispose();
  }

  void _finishPayment(BuildContext context, PosProvider provider, String method, double amount) {
    final completedOrder = provider.completePayment(
      paymentMethod: method,
      amountPaid: amount,
    );

    if (completedOrder != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentSuccessScreen(order: completedOrder),
        ),
      );
    }
  }

  Widget _buildModeTile(String title, IconData icon, Color color) {
    final isSelected = _selectedPaymentMode == title;
    return InkWell(
      onTap: () => setState(() => _selectedPaymentMode = title),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreenLight : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : AppColors.borderLight,
            width: isSelected ? 1.8 : 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppColors.primaryGreen : color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 15,
                  color: isSelected ? AppColors.primaryGreen : AppColors.textDark,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.primaryGreen, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final activeOrder = provider.activeOrder;

    if (activeOrder == null) {
      return const Scaffold(body: Center(child: Text('No active order for payment')));
    }

    final grandTotal = activeOrder.grandTotal;
    final cashReceived = double.tryParse(_cashReceivedController.text) ?? grandTotal;
    final changeDue = (cashReceived - grandTotal).clamp(0.0, double.infinity);
    final shortBy = (grandTotal - cashReceived).clamp(0.0, double.infinity);

    // Quick cash chip suggestions (deduped, never below the total)
    final quickAmounts = <double>{
      grandTotal,
      (grandTotal / 100).ceil() * 100.0,
      (grandTotal / 500).ceil() * 500.0,
      ((grandTotal / 500).ceil() * 500.0) + 500.0,
    }.where((a) => a >= grandTotal && a > 0).toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Select Payment Method', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Total Payable Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderLight),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text('Total Amount to Collect', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        '₹${grandTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w900,
                          fontSize: 38,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${activeOrder.totalItemCount} Items · ${activeOrder.orderNumber} · Table ${activeOrder.tableNumber ?? "Counter"}',
                        style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const SizedBox(height: 16),

                // Payment Modes Grid
                const Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                _buildModeTile('Cash', Icons.payments_outlined, AppColors.vegGreen),
                const SizedBox(height: 8),
                _buildModeTile('UPI', Icons.qr_code_2_outlined, AppColors.infoBlue),
                const SizedBox(height: 8),
                _buildModeTile('Card', Icons.credit_card_outlined, AppColors.saffronAmber),
                const SizedBox(height: 8),
                _buildModeTile('Credit / Pay Later', Icons.account_balance_wallet_outlined, AppColors.textMuted),

                const SizedBox(height: 20),

                // Mode Specific Content
                if (_selectedPaymentMode == 'Cash') ...[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cash Tendered', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _cashReceivedController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.currency_rupee),
                            labelText: 'Cash Received (₹)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Quick Cash Buttons
                        Wrap(
                          spacing: 8,
                          children: quickAmounts.map((amt) {
                            return ActionChip(
                              label: Text('₹${amt.toStringAsFixed(0)}'),
                              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              onPressed: () {
                                setState(() {
                                  _cashReceivedController.text = amt.toStringAsFixed(0);
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const Divider(height: 24, color: AppColors.borderLight),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              shortBy > 0.005 ? 'Short by:' : 'Change Due to Return:',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            Text(
                              '₹${(shortBy > 0.005 ? shortBy : changeDue).toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                                color: shortBy > 0.005 ? AppColors.nonVegRed : AppColors.vegGreen,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else if (_selectedPaymentMode == 'UPI') ...[
                  _UpiQrPanel(order: activeOrder),
                ] else if (_selectedPaymentMode == 'Card') ...[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Card machine: POS-01 (PineLabs)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _cardRefController,
                          decoration: const InputDecoration(
                            labelText: 'Card Transaction Reference / Approval Code',
                            prefixIcon: Icon(Icons.pin, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.assignment_ind, size: 36, color: AppColors.primaryGreen),
                        SizedBox(height: 8),
                        Text('Customer Credit / Pay Later ledger requires manager authorization.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Complete Payment CTA
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.vegGreen),
                    onPressed: () async {
                      if (_selectedPaymentMode == 'Credit / Pay Later') {
                        final managerPin = await ManagerPinDialog.show(
                          context,
                          title: 'Credit Authorization',
                          description: 'Manager approval required for customer credit ledger.',
                        );
                        if (managerPin == null) return;
                      }
                      if (!context.mounted) return;
                      if (_selectedPaymentMode == 'Cash' && shortBy > 0.005) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Cash received is short by ₹${shortBy.toStringAsFixed(0)}'),
                            backgroundColor: AppColors.nonVegRed,
                          ),
                        );
                        return;
                      }
                      final ok = await showConfirmDialog(
                        context,
                        title: 'Complete payment?',
                        message:
                            'Collect ₹${grandTotal.toStringAsFixed(0)} via $_selectedPaymentMode? The order will close and this cannot be undone.',
                        confirmLabel: 'Collect Payment',
                        isDanger: false,
                      );
                      if (!ok || !context.mounted) return;

                      _finishPayment(
                        context,
                        provider,
                        _selectedPaymentMode,
                        _selectedPaymentMode == 'Cash' ? cashReceived : grandTotal,
                      );
                    },
                    child: Text(
                      'Complete ${_selectedPaymentMode.toUpperCase()} Payment',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
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

/// Renders the customer UPI QR for the current bill. Priority: an uploaded
/// override image, else a per-bill QR generated from the settings UPI ID with
/// the amount + payee + order note pre-filled.
class _UpiQrPanel extends StatelessWidget {
  final RestaurantOrder order;

  const _UpiQrPanel({required this.order});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final settings = provider.settings;
    final upiId = validateUpiId(settings.upiId);
    final overrideUrl = resolveMediaUrl(settings.upiQrImage,
        apiBase: provider.apiBaseUrl);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          if (overrideUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                overrideUrl,
                width: 190,
                height: 190,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => _qrPlaceholder(),
              ),
            )
          else if (upiId != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderMedium),
              ),
              child: QrImageView(
                data: buildUpiUri(
                  upiId,
                  payeeName: settings.upiName.isEmpty ? null : settings.upiName,
                  amount: order.grandTotal,
                  note: order.orderNumber,
                ),
                version: QrVersions.auto,
                size: 190,
              ),
            )
          else
            _qrPlaceholder(),
          const SizedBox(height: 12),
          if (upiId == null && overrideUrl.isEmpty)
            const Text(
              'UPI is not configured. Ask the admin to add a UPI ID in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            )
          else ...[
            if (settings.upiName.isNotEmpty)
              Text(settings.upiName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            if (upiId != null)
              Text(upiId, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              'Scan & Pay ₹${order.grandTotal.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.vegGreen),
            ),
          ],
        ],
      ),
    );
  }

  Widget _qrPlaceholder() => Container(
        width: 190,
        height: 190,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderMedium),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner, size: 60, color: AppColors.textDark),
            SizedBox(height: 8),
            Text('UPI QR', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      );
}

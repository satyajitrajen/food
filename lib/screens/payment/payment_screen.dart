import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/format.dart';
import '../../core/media.dart';
import '../../core/payments/upi_qr.dart';
import '../../core/theme/app_theme.dart';
import '../../models/customer_model.dart';
import '../../models/order_model.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/bill_breakdown.dart';
import '../../widgets/custom_badge.dart';
import '../modals/add_charge_dialog.dart';
import '../modals/apply_discount_dialog.dart';
import '../modals/manager_pin_dialog.dart';
import '../receipt/payment_success_screen.dart';

/// Bill + payment in one screen: review the bill, adjust discount/charges,
/// pick the tender (or split it) and settle. Tapping "Collect" is the
/// confirmation, so there is no extra dialog.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

enum _Mode { cash, upi, card, split, credit }

class _SplitLeg {
  PaymentMethod method;
  final TextEditingController amount;
  _SplitLeg(this.method, double value)
      : amount = TextEditingController(text: rupeeInput(value));
}

class _PaymentScreenState extends State<PaymentScreen> {
  _Mode _mode = _Mode.cash;
  bool _itemsExpanded = false;
  final TextEditingController _cashReceivedController = TextEditingController();
  final TextEditingController _refController = TextEditingController();
  final List<_SplitLeg> _legs = [];
  Customer? _creditCustomer;
  String? _error;

  @override
  void initState() {
    super.initState();
    final total = context.read<PosProvider>().activeOrder?.grandTotal ?? 0.0;
    _cashReceivedController.text = rupeeInput(total);
  }

  @override
  void dispose() {
    _cashReceivedController.dispose();
    _refController.dispose();
    for (final l in _legs) {
      l.amount.dispose();
    }
    super.dispose();
  }

  double _parse(String s) => double.tryParse(s.replaceAll(',', '').trim()) ?? 0.0;

  void _ensureSplitLegs(double total) {
    if (_legs.isNotEmpty) return;
    final half = roundMoney(total / 2);
    _legs
      ..add(_SplitLeg(PaymentMethod.cash, half))
      ..add(_SplitLeg(PaymentMethod.upi, roundMoney(total - half)));
  }

  Future<void> _collect(PosProvider provider, RestaurantOrder order) async {
    final total = order.grandTotal;
    setState(() => _error = null);
    // Every sale is booked to an open cash shift (the server refuses
    // payments without one).
    if (provider.apiEnabled && provider.currentShift == null) {
      setState(() => _error = 'Open a shift first (Shift & Cash → Open shift), then collect payment.');
      return;
    }
    RestaurantOrder? done;
    switch (_mode) {
      case _Mode.cash:
        final received = _parse(_cashReceivedController.text);
        if (received + 0.005 < total) {
          setState(() => _error = 'Cash received is short by ${formatInr(total - received)}');
          return;
        }
        done = provider.completePayment(paymentMethod: 'Cash', amountPaid: received);
        break;
      case _Mode.upi:
      case _Mode.card:
        done = provider.completePayment(
          paymentMethod: _mode == _Mode.upi ? 'UPI' : 'Card',
          amountPaid: total,
          reference: _refController.text,
        );
        break;
      case _Mode.credit:
        final customer = _creditCustomer;
        if (customer == null) {
          setState(() => _error = 'Pick the customer this bill is credited to');
          return;
        }
        final pin = await ManagerPinDialog.show(
          context,
          title: 'Approve credit',
          description: "Bill ${formatInr(total)} to ${customer.name}'s account.",
        );
        if (pin == null || !mounted) return;
        done = provider.completePayment(
          paymentMethod: 'Credit',
          amountPaid: total,
          creditCustomerId: customer.id,
        );
        break;
      case _Mode.split:
        final legs = [
          for (final l in _legs)
            if (_parse(l.amount.text) > 0)
              (method: l.method.label, amount: _parse(l.amount.text)),
        ];
        final allocated = legs.fold<double>(0, (s, l) => s + l.amount);
        if ((allocated - total).abs() > 0.005) {
          setState(() => _error = allocated < total
              ? '${formatInr(total - allocated)} is still unallocated'
              : 'The parts exceed the bill by ${formatInr(allocated - total)}');
          return;
        }
        done = provider.completePayment(
          paymentMethod: legs.first.method,
          amountPaid: total,
          splits: legs,
          reference: _refController.text,
        );
        break;
    }
    if (!mounted) return;
    final completed = done;
    if (completed == null) {
      setState(() => _error = 'Payment could not be recorded. Check the amounts and try again.');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => PaymentSuccessScreen(order: completed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final order = provider.activeOrder;

    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bill & Payment')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This order is no longer open.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }

    final total = order.grandTotal;
    if (_mode == _Mode.split) _ensureSplitLegs(total);
    final where =
        order.tableNumber != null ? 'Table ${order.tableNumber}' : order.orderTypeLabel;

    return Scaffold(
      appBar: AppBar(title: const Text('Bill & Payment')),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$where · ${order.orderNumber}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _itemsExpanded = !_itemsExpanded),
                            icon: Icon(_itemsExpanded ? Icons.expand_less : Icons.expand_more),
                            label: Text(plural(order.totalItemCount, 'item')),
                          ),
                        ],
                      ),
                      if (_itemsExpanded)
                        for (final item in order.activeItems)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: VegMark(isVeg: item.menuItem.isVeg, size: 12),
                                ),
                                const SizedBox(width: 8),
                                Text('${item.quantity} × ',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primaryGreen)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.displayName,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                      if (item.selectedModifiers.isNotEmpty)
                                        Text(
                                          '+ ${item.selectedModifiers.map((m) => m.name).join(', ')}',
                                          style: const TextStyle(
                                              color: AppColors.textMuted, fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(formatInr(item.totalPrice),
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                      const Divider(height: 20, color: AppColors.borderLight),
                      BillBreakdown(order: order),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => ApplyDiscountDialog.show(context),
                              icon: const Icon(Icons.percent, size: 18),
                              label: Text(
                                  order.computedDiscount > 0 ? 'Edit discount' : 'Discount'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => AddChargeDialog.show(context),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Charges'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _modeChip(_Mode.cash, 'Cash', Icons.payments_outlined),
                    _modeChip(_Mode.upi, 'UPI', Icons.qr_code_2_outlined),
                    _modeChip(_Mode.card, 'Card', Icons.credit_card_outlined),
                    _modeChip(_Mode.split, 'Split', Icons.call_split),
                    _modeChip(_Mode.credit, 'Credit (pay later)',
                        Icons.account_balance_wallet_outlined),
                  ],
                ),
                const SizedBox(height: 12),
                _modeBody(order),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppColors.danger, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () => _collect(provider, order),
                    child: Text(
                      _mode == _Mode.credit
                          ? 'Bill ${formatInr(total)} to customer'
                          : 'Collect ${formatInr(total)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.creamCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: child,
      );

  Widget _modeChip(_Mode mode, String label, IconData icon) => ChoiceChip(
        selected: _mode == mode,
        onSelected: (_) => setState(() {
          _mode = mode;
          _error = null;
        }),
        avatar: Icon(icon, size: 18),
        label: Text(label),
      );

  Widget _modeBody(RestaurantOrder order) {
    final total = order.grandTotal;
    switch (_mode) {
      case _Mode.cash:
        final received = _parse(_cashReceivedController.text);
        final quick = <double>{
          total,
          (total / 100).ceil() * 100.0,
          (total / 500).ceil() * 500.0,
          ((total / 500).ceil() * 500.0) + 500.0,
        }.where((a) => a >= total && a > 0).toList()
          ..sort();
        final short = total - received;
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _cashReceivedController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                onChanged: (_) => setState(() => _error = null),
                decoration: const InputDecoration(labelText: 'Cash received', prefixText: '₹ '),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final amt in quick)
                    ActionChip(
                      label: Text(formatInr(amt)),
                      onPressed: () =>
                          setState(() => _cashReceivedController.text = rupeeInput(amt)),
                    ),
                ],
              ),
              const Divider(height: 24, color: AppColors.borderLight),
              Row(
                children: [
                  Expanded(
                    child: Text(short > 0.005 ? 'Short by' : 'Change to return',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    formatInr(short > 0.005 ? short : -short),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: short > 0.005 ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      case _Mode.upi:
        return Column(
          children: [
            _UpiQrPanel(order: order),
            const SizedBox(height: 10),
            _refField('UPI reference (optional)'),
          ],
        );
      case _Mode.card:
        return _card(child: _refField('Card approval code (optional)'));
      case _Mode.credit:
        return _card(
          child: _CreditCustomerPicker(
            selected: _creditCustomer,
            onChanged: (c) => setState(() {
              _creditCustomer = c;
              _error = null;
            }),
          ),
        );
      case _Mode.split:
        final allocated = _legs.fold<double>(0, (s, l) => s + _parse(l.amount.text));
        final remaining = total - allocated;
        return _card(
          child: Column(
            children: [
              for (var i = 0; i < _legs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      DropdownButton<PaymentMethod>(
                        value: _legs[i].method,
                        onChanged: (m) =>
                            setState(() => _legs[i].method = m ?? _legs[i].method),
                        items: [
                          for (final m in [
                            PaymentMethod.cash,
                            PaymentMethod.upi,
                            PaymentMethod.card,
                          ])
                            DropdownMenuItem(value: m, child: Text(m.label)),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _legs[i].amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() => _error = null),
                          decoration: const InputDecoration(prefixText: '₹ ', isDense: true),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove this part',
                        onPressed: _legs.length <= 2
                            ? null
                            : () => setState(() => _legs.removeAt(i).amount.dispose()),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _legs
                        .add(_SplitLeg(PaymentMethod.card, remaining > 0 ? remaining : 0))),
                    icon: const Icon(Icons.add),
                    label: const Text('Add part'),
                  ),
                  const Spacer(),
                  Text(
                    remaining.abs() < 0.005
                        ? 'Fully allocated'
                        : remaining > 0
                            ? '${formatInr(remaining)} left'
                            : '${formatInr(-remaining)} over',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: remaining.abs() < 0.005 ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ],
              ),
              _refField('Card / UPI reference (optional)'),
            ],
          ),
        );
    }
  }

  Widget _refField(String label) => TextField(
        controller: _refController,
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.tag, size: 18)),
      );
}

/// Search existing customers by name/phone, or add one inline, for a credit
/// (pay later) bill.
class _CreditCustomerPicker extends StatefulWidget {
  final Customer? selected;
  final ValueChanged<Customer?> onChanged;
  const _CreditCustomerPicker({required this.selected, required this.onChanged});

  @override
  State<_CreditCustomerPicker> createState() => _CreditCustomerPickerState();
}

class _CreditCustomerPickerState extends State<_CreditCustomerPicker> {
  final _query = TextEditingController();
  final _name = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _query.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final sel = widget.selected;
    if (sel != null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(sel.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('${sel.phone} · owes ${formatInr(sel.outstandingCredit)}'),
        trailing: TextButton(onPressed: () => widget.onChanged(null), child: const Text('Change')),
      );
    }
    final q = _query.text.trim().toLowerCase();
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final matches = q.isEmpty
        ? const <Customer>[]
        : provider.customers
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                (digits.isNotEmpty && c.phone.replaceAll(RegExp(r'\D'), '').contains(digits)))
            .take(6)
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _query,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Customer name or mobile',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        for (final c in matches)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.name),
            subtitle: Text(c.phone),
            onTap: () => widget.onChanged(c),
          ),
        if (q.isNotEmpty && matches.isEmpty && !_adding)
          TextButton.icon(
            onPressed: () => setState(() => _adding = true),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('New customer'),
          ),
        if (_adding) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              helperText: digits.length < 10 ? 'Type the 10-digit mobile in the search box' : null,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _name.text.trim().isEmpty && digits.length < 10
                  ? null
                  : () {
                      if (_name.text.trim().isEmpty || digits.length < 10) return;
                      final c = Customer(
                        id: 'cust-${DateTime.now().millisecondsSinceEpoch}',
                        name: _name.text.trim(),
                        phone: digits,
                        visits: 0,
                      );
                      provider.addCustomer(c);
                      widget.onChanged(c);
                    },
              child: const Text('Add & select'),
            ),
          ),
        ],
      ],
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
    final overrideUrl = resolveMediaUrl(settings.upiQrImage, apiBase: provider.apiBaseUrl);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.creamCard,
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
              'UPI is not set up. A manager can add the UPI ID in Settings.',
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
              'Scan & pay ${formatInr(order.grandTotal)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.success),
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
          color: AppColors.creamSubtle,
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

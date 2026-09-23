import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/order_model.dart';
import '../../providers/pos_provider.dart';
import '../modals/refund_dialog.dart';
import '../receipt/payment_success_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _selectedPaymentFilter = 'All';
  final TextEditingController _searchController = TextEditingController();
  // Period filter: 'Today' | '7D' | '30D' | 'All' | 'Custom'
  String _period = 'All';
  DateTimeRange? _customRange;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _inPeriod(RestaurantOrder tx) {
    final paid = tx.paidAt;
    if (paid == null) return _period == 'All';
    switch (_period) {
      case 'Today':
        final now = DateTime.now();
        return paid.year == now.year && paid.month == now.month && paid.day == now.day;
      case '7D':
        return paid.isAfter(DateTime.now().subtract(const Duration(days: 7)));
      case '30D':
        return paid.isAfter(DateTime.now().subtract(const Duration(days: 30)));
      case 'Custom':
        final r = _customRange;
        if (r == null) return true;
        final start = DateTime(r.start.year, r.start.month, r.start.day);
        final end = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
        return !paid.isBefore(start) && !paid.isAfter(end);
      default:
        return true;
    }
  }

  String _periodLabel(String p) {
    switch (p) {
      case '7D':
        return 'Last 7 days';
      case '30D':
        return 'Last 30 days';
      default:
        return p;
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _period = 'Custom';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final transactions = provider.completedTransactions;

    final filtered = transactions.where((tx) {
      if (_selectedPaymentFilter != 'All' && tx.paymentMethod != _selectedPaymentFilter) {
        return false;
      }
      if (!_inPeriod(tx)) return false;
      if (_searchController.text.isNotEmpty) {
        final q = _searchController.text.toLowerCase();
        final matchInv = (tx.invoiceNumber ?? '').toLowerCase().contains(q);
        final matchCust = (tx.customerName ?? '').toLowerCase().contains(q);
        if (!matchInv && !matchCust) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Past Transactions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          // Search & Filter Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search invoice number (e.g. INV-1040) or customer...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    fillColor: AppColors.creamSubtle,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                // Date period filter with custom range
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in ['Today', '7D', '30D', 'All'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_periodLabel(p)),
                            selected: _period == p,
                            selectedColor: AppColors.primaryGreen,
                            labelStyle: TextStyle(
                              color: _period == p ? Colors.white : AppColors.textDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            onSelected: (_) => setState(() => _period = p),
                          ),
                        ),
                      ChoiceChip(
                        label: Text(
                          _period == 'Custom' && _customRange != null
                              ? '${DateFormat('dd MMM').format(_customRange!.start)} – ${DateFormat('dd MMM').format(_customRange!.end)}'
                              : 'Custom range',
                        ),
                        selected: _period == 'Custom',
                        selectedColor: AppColors.primaryGreen,
                        labelStyle: TextStyle(
                          color: _period == 'Custom' ? Colors.white : AppColors.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        onSelected: (_) => _pickCustomRange(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Cash', 'UPI', 'Card'].map((mode) {
                      final isSelected = _selectedPaymentFilter == mode;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(mode),
                          selected: isSelected,
                          selectedColor: AppColors.primaryGreen,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textDark,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          onSelected: (_) => setState(() => _selectedPaymentFilter = mode),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),

          // Transactions List
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No transactions match your search filter.', style: TextStyle(color: AppColors.textMuted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final tx = filtered[index];
                      final dateStr = tx.paidAt != null
                          ? DateFormat('dd MMM, hh:mm a').format(tx.paidAt!)
                          : 'Recent';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderLight),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                tx.invoiceNumber ?? tx.orderNumber,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                              Text(
                                '₹${tx.grandTotal.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.primaryGreen),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.creamSubtle,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      tx.paymentMethod ?? 'Cash',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      tx.tableNumber != null ? 'Table ${tx.tableNumber}' : tx.orderTypeLabel,
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '· $dateStr',
                                      style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    ),
                                    onPressed: () => _printBill(context, tx),
                                    icon: const Icon(Icons.print, size: 14),
                                    label: const Text('Print', style: TextStyle(fontSize: 12)),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      side: const BorderSide(color: AppColors.nonVegRed),
                                      foregroundColor: AppColors.nonVegRed,
                                    ),
                                    onPressed: () => RefundDialog.show(context, tx),
                                    icon: const Icon(Icons.currency_exchange, size: 14),
                                    label: const Text('Refund', style: TextStyle(fontSize: 12)),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      backgroundColor: AppColors.primaryGreen,
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => PaymentSuccessScreen(order: tx)),
                                      );
                                    },
                                    icon: const Icon(Icons.receipt_long, size: 14),
                                    label: const Text('View Bill', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _printBill(BuildContext context, RestaurantOrder tx) async {
    final provider = context.read<PosProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (!provider.settings.allowReprint) {
      messenger.showSnackBar(const SnackBar(content: Text('Reprint is disabled in Settings')));
      return;
    }
    final ok = await provider.reprintReceipt(tx);
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Bill sent to the printer' : (provider.printerError ?? 'Printer not reachable')),
      backgroundColor: ok ? AppColors.vegGreen : AppColors.nonVegRed,
    ));
  }
}

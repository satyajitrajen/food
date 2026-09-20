import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/expense_model.dart';
import '../../widgets/stat_kpi_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/dialog_controller_scope.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  // Period filter: 'Today' | '7D' | '30D' | 'All' | 'Custom'
  String _period = 'All';
  DateTimeRange? _customRange;

  bool _inPeriod(DateTime d) {
    switch (_period) {
      case 'Today':
        final now = DateTime.now();
        return d.year == now.year && d.month == now.month && d.day == now.day;
      case '7D':
        return d.isAfter(DateTime.now().subtract(const Duration(days: 7)));
      case '30D':
        return d.isAfter(DateTime.now().subtract(const Duration(days: 30)));
      case 'Custom':
        final r = _customRange;
        if (r == null) return true;
        final start = DateTime(r.start.year, r.start.month, r.start.day);
        final end = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
        return !d.isBefore(start) && !d.isAfter(end);
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

  void _showAddExpenseDialog(BuildContext context, PosProvider provider) {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final vendorCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    ExpenseCategory cat = ExpenseCategory.miscellaneous;
    String method = 'Cash';

    showDialog(
      context: context,
      builder: (ctx) => DialogControllerScope(
        controllers: [titleCtrl, amountCtrl, vendorCtrl, descCtrl],
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Operating Expense', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Expense Title (e.g. Fresh Veggies)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee)),
                  ),
                  const SizedBox(height: 12),
                  const Text('Category:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  DropdownButton<ExpenseCategory>(
                    value: cat,
                    isExpanded: true,
                    items: ExpenseCategory.values.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text(c.name.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (v) => setDialogState(() => cat = v!),
                  ),
                  const SizedBox(height: 12),
                  const Text('Payment Method:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  DropdownButton<String>(
                    value: method,
                    isExpanded: true,
                    items: ['Cash', 'UPI', 'Card', 'Bank Transfer'].map((m) {
                      return DropdownMenuItem(value: m, child: Text(m));
                    }).toList(),
                    onChanged: (v) => setDialogState(() => method = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: vendorCtrl,
                    decoration: const InputDecoration(labelText: 'Vendor / Beneficiary'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text) ?? 0.0;
                if (amt <= 0 || titleCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a title and an amount greater than zero'),
                      backgroundColor: AppColors.nonVegRed,
                    ),
                  );
                  return;
                }

                provider.addExpense(
                  Expense(
                    id: 'exp-${DateTime.now().millisecondsSinceEpoch}',
                    title: titleCtrl.text.trim(),
                    category: cat,
                    amount: amt,
                    date: DateTime.now(),
                    paymentMethod: method,
                    vendor: vendorCtrl.text.trim().isNotEmpty ? vendorCtrl.text.trim() : null,
                    description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                  ),
                );
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✓ Added expense ₹${amt.toStringAsFixed(0)}'), backgroundColor: AppColors.vegGreen),
                );
              },
              child: const Text('Save Expense'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final expenses = provider.expenses.where((e) => _inPeriod(e.date)).toList();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Expense Management', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
            onPressed: () => _showAddExpenseDialog(context, provider),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Expense'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Summary Cards
            Row(
              children: [
                Expanded(
                  child: StatKpiCard(
                    title: "Today's Expenses",
                    value: '₹${provider.todayExpenses.toStringAsFixed(0)}',
                    icon: Icons.calendar_today_outlined,
                    iconColor: AppColors.primaryGreen,
                    iconBgColor: AppColors.primaryGreenLight,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: StatKpiCard(
                    title: 'This Month Total',
                    value: '₹${provider.monthExpenses.toStringAsFixed(0)}',
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: AppColors.infoBlue,
                    iconBgColor: AppColors.infoBlueBg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

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
            const SizedBox(height: 20),

            // Expense List Section
            const Text('Logged Expenses', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            if (expenses.isEmpty)
              const Center(child: Text('No expenses recorded yet.'))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: expenses.length,
                itemBuilder: (context, index) {
                  final exp = expenses[index];
                  final dateStr = DateFormat('dd MMM yyyy').format(exp.date);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.creamSubtle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.receipt_long, color: AppColors.primaryGreen, size: 22),
                      ),
                      title: Text(exp.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      subtitle: Text(
                        '${exp.categoryLabel} · ${exp.paymentMethod} · $dateStr ${exp.vendor != null ? "(${exp.vendor})" : ""}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '₹${exp.amount.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.nonVegRed),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.textLight),
                            onPressed: () async {
                              final ok = await showConfirmDialog(
                                context,
                                title: 'Delete expense?',
                                message:
                                    'Delete "${exp.title}" ₹${exp.amount.toStringAsFixed(0)}? Cash expenses adjust the drawer. This cannot be undone.',
                                confirmLabel: 'Delete',
                              );
                              if (!ok || !context.mounted) return;
                              provider.deleteExpense(exp.id);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    ),
  );
}
}

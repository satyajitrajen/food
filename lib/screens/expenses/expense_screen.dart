import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/expense_model.dart';
import '../../widgets/stat_kpi_card.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  void _showAddExpenseDialog(BuildContext context, PosProvider provider) {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final vendorCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    ExpenseCategory cat = ExpenseCategory.miscellaneous;
    String method = 'Cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
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
    ).then((_) {
      titleCtrl.dispose();
      amountCtrl.dispose();
      vendorCtrl.dispose();
      descCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final expenses = provider.expenses;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Expense Management', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
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
                    iconColor: AppColors.primaryOrange,
                    iconBgColor: AppColors.primaryOrangeLight,
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
                        child: const Icon(Icons.receipt_long, color: AppColors.primaryOrange, size: 22),
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
                            onPressed: () => provider.deleteExpense(exp.id),
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

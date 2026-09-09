import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../models/customer_model.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final TextEditingController _searchController = TextEditingController();

  void _showAddCustomerDialog(BuildContext context, PosProvider provider) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Customer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Customer Full Name', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile Number', prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (Optional)', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address (for delivery)', prefixIcon: Icon(Icons.home_outlined)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) return;
              provider.addCustomer(
                Customer(
                  id: 'c-${DateTime.now().millisecondsSinceEpoch}',
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  email: emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null,
                  address: addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : null,
                  lastVisit: DateTime.now(),
                ),
              );
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✓ Customer added successfully!'), backgroundColor: AppColors.vegGreen),
              );
            },
            child: const Text('Save Customer'),
          ),
        ],
      ),
    );
  }

  void _showCreditDialog(BuildContext context, PosProvider provider, Customer cust, String kind) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final isSettle = kind == 'settlement';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isSettle ? 'Settle Credit — ${cust.name}' : 'Book Credit Sale — ${cust.name}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSettle)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Outstanding: ₹${cust.outstandingCredit.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppColors.nonVegRed, fontWeight: FontWeight.w700),
                    ),
                  ),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₹)', prefixIcon: Icon(Icons.currency_rupee)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Reason (required)', prefixIcon: Icon(Icons.note_outlined)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
              final ok = provider.bookCustomerCredit(
                customerId: cust.id,
                kind: kind,
                amount: amount,
                reason: reasonCtrl.text.trim(),
              );
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? (isSettle ? '✓ Settlement recorded' : '✓ Credit sale booked')
                      : 'Invalid amount or reason (settlement cannot exceed outstanding)'),
                  backgroundColor: ok ? AppColors.vegGreen : AppColors.nonVegRed,
                ),
              );
            },
            child: Text(isSettle ? 'Record Settlement' : 'Book Credit'),
          ),
        ],
      ),
    );
  }

  /// W6 (FR-C1): shows the server-side credit ledger; falls back to a clear
  /// offline notice when the terminal can't reach the API.
  void _showCreditLogDialog(BuildContext context, PosProvider provider, Customer cust) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 360,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: provider.fetchCreditLog(cust.id),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              }
              final entries = snap.data ?? const [];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Credit History — ${cust.name}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Text(
                              provider.isOfflineMode
                                  ? 'Offline — credit history lives on the server.'
                                  : 'No credit entries recorded yet.',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: entries.length,
                            itemBuilder: (context, i) {
                              final e = entries[i];
                              final kind = e['kind']?.toString() ?? 'sale';
                              final amount = ((e['amount_paise'] as num?)?.toDouble() ?? 0) / 100.0;
                              final ts = DateTime.tryParse(e['ts']?.toString() ?? '');
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  kind == 'settlement' ? Icons.payments : Icons.add_card,
                                  color: kind == 'settlement' ? AppColors.vegGreen : AppColors.nonVegRed,
                                ),
                                title: Text(
                                  '${kind == 'settlement' ? 'Settlement' : 'Credit sale'}  ₹${amount.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                subtitle: Text(
                                  '${e['reason'] ?? '—'}${ts != null ? ' · ${ts.day}/${ts.month}/${ts.year}' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final customers = provider.customers.where((c) {
      if (_searchController.text.isNotEmpty) {
        final q = _searchController.text.toLowerCase();
        return c.name.toLowerCase().contains(q) || c.phone.contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Customer Directory', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            onPressed: () => _showAddCustomerDialog(context, provider),
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text('Add Customer'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search customer by name or phone...',
                prefixIcon: const Icon(Icons.search),
                fillColor: AppColors.creamSubtle,
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: customers.length,
              itemBuilder: (context, index) {
                final cust = customers[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primaryOrangeLight,
                      child: Text(
                        cust.name.isNotEmpty ? cust.name.substring(0, 1).toUpperCase() : '?',
                        style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w800),
                      ),
                    ),
                    title: Text(cust.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('Phone: ${cust.phone} · Visits: ${cust.visits}'),
                        if (cust.outstandingCredit > 0)
                          Text(
                            'Outstanding Credit: ₹${cust.outstandingCredit.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.nonVegRed, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Lifetime Spend', style: TextStyle(color: AppColors.textLight, fontSize: 11)),
                        Text(
                          '₹${cust.lifetimeSpend.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primaryOrange),
                        ),
                      ],
                    ),
                    onTap: () => showModalBottomSheet(
                      context: context,
                      builder: (bctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 8),
                            ListTile(
                              leading: const Icon(Icons.add_card, color: AppColors.primaryOrange),
                              title: const Text('Book credit sale (house tab)'),
                              onTap: () {
                                Navigator.of(bctx).pop();
                                _showCreditDialog(context, provider, cust, 'sale');
                              },
                            ),
                            if (cust.outstandingCredit > 0)
                              ListTile(
                                leading: const Icon(Icons.payments, color: AppColors.vegGreen),
                                title: Text('Settle outstanding (₹${cust.outstandingCredit.toStringAsFixed(0)})'),
                                onTap: () {
                                  Navigator.of(bctx).pop();
                                  _showCreditDialog(context, provider, cust, 'settlement');
                                },
                              ),
                            ListTile(
                              leading: const Icon(Icons.history, color: AppColors.infoBlue),
                              title: const Text('Credit history (FR-C1 audit trail)'),
                              onTap: () {
                                Navigator.of(bctx).pop();
                                _showCreditLogDialog(context, provider, cust);
                              },
                            ),
                          ],
                        ),
                      ),
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
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validation.dart';
import '../../providers/pos_provider.dart';
import '../../models/inventory_model.dart';
import '../../widgets/confirm_dialog.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _serverAdjustments = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadServerAdjustments();
  }

  Future<void> _loadServerAdjustments() async {
    final provider = context.read<PosProvider>();
    final list = await provider.fetchStockAdjustments();
    if (mounted) setState(() => _serverAdjustments = list);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAdjustStockDialog(BuildContext context, InventoryItem item, PosProvider provider) {
    final qtyCtrl = TextEditingController();
    bool isIncrease = true;
    String reason = 'Purchase Arrival';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Adjust Stock — ${item.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Available Stock: ${item.availableStock} ${item.unit}'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('+ Increase')),
                          selected: isIncrease,
                          selectedColor: AppColors.vegGreen,
                          labelStyle: TextStyle(color: isIncrease ? Colors.white : AppColors.textDark, fontWeight: FontWeight.w700),
                          onSelected: (_) => setDialogState(() => isIncrease = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('− Decrease')),
                          selected: !isIncrease,
                          selectedColor: AppColors.nonVegRed,
                          labelStyle: TextStyle(color: !isIncrease ? Colors.white : AppColors.textDark, fontWeight: FontWeight.w700),
                          onSelected: (_) => setDialogState(() => isIncrease = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Quantity (${item.unit})'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Reason:'),
                  DropdownButton<String>(
                    value: reason,
                    isExpanded: true,
                    items: ['Purchase Arrival', 'Wastage / Spoiled', 'Damage', 'Staff Consumption', 'Manual Audit Correction']
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => reason = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final qty = double.tryParse(qtyCtrl.text) ?? 0.0;
                if (qty <= 0) return;
                final ok = await showConfirmDialog(
                  context,
                  title: isIncrease ? 'Increase stock?' : 'Decrease stock?',
                  message: isIncrease
                      ? 'Add $qty ${item.unit} to ${item.name} ($reason)?'
                      : 'Remove $qty ${item.unit} from ${item.name} ($reason)? Decreases can wipe stock and cannot be undone.',
                  confirmLabel: 'Confirm Adjustment',
                );
                if (!ok || !context.mounted) return;
                provider.adjustStock(item.id, isIncrease ? qty : -qty, reason);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✓ Updated stock for ${item.name}'), backgroundColor: AppColors.vegGreen),
                );
              },
              child: const Text('Confirm Adjustment'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Inventory & Raw Materials', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Add Inventory Item',
            icon: const Icon(Icons.add),
            onPressed: provider.canManage ? () => _showAddItemDialog(context, provider) : null,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.primaryGreen,
          indicatorColor: AppColors.primaryGreen,
          unselectedLabelColor: AppColors.textDark,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: 'Ingredients (${provider.inventory.length})'),
            Tab(text: 'Low Stock (${provider.lowStockItems.length})'),
            Tab(text: 'Suppliers (${provider.suppliers.length})'),
            Tab(text: 'Purchases (${provider.purchases.length})'),
            const Tab(text: 'Stock Log'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabController,
          children: [
            // All Ingredients
            _buildInventoryList(context, provider.inventory, provider),
            // Low Stock Filtered
            _buildInventoryList(context, provider.lowStockItems, provider),
            // Suppliers List
            _buildSuppliersList(context, provider.suppliers, provider),
            // Purchases (W5)
            _buildPurchasesList(context, provider),
            // Stock adjustment audit log (W7 — server truth when online)
            _buildAdjustmentsLog(context, provider, _serverAdjustments),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryList(BuildContext context, List<InventoryItem> items, PosProvider provider) {
    if (items.isEmpty) {
      return const Center(child: Text('No inventory items in this list'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final provenance = <String>[
          if ((item.batchNo ?? '').isNotEmpty) 'Batch ${item.batchNo}',
          if ((item.rackNo ?? '').isNotEmpty) 'Rack ${item.rackNo}',
          if (item.purchasedAt != null)
            'Purchased ${DateFormat('dd MMM yy').format(item.purchasedAt!)}',
        ].join(' · ');

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: item.isLowStock ? AppColors.nonVegRed : AppColors.borderLight),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                        if (item.isLowStock) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.nonVegRedBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('LOW STOCK', style: TextStyle(color: AppColors.nonVegRed, fontWeight: FontWeight.w800, fontSize: 10)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Available: ${item.availableStock} ${item.unit} · Min: ${item.minStock} ${item.unit} · ₹${item.costPerUnit.toStringAsFixed(0)}/unit',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    if (provenance.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        provenance,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textLight, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => _showAdjustStockDialog(context, item, provider),
                child: const Text('Adjust'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuppliersList(BuildContext context, List<Supplier> suppliers, PosProvider provider) {
    // 'All' | '7D' | '30D' — filters the payment history shown per supplier.
    String period = 'All';
    return StatefulBuilder(
      builder: (context, setTabState) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: provider.canManage
            ? FloatingActionButton.extended(
                heroTag: 'addSupplier',
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_business, size: 20),
                label: const Text('Add Supplier'),
                onPressed: () => _showAddSupplierDialog(context, provider),
              )
            : null,
        body: suppliers.isEmpty
            ? const Center(child: Text('No suppliers yet'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: suppliers.length,
                itemBuilder: (context, index) {
                  final sup = suppliers[index];
                  final payments = provider.supplierPaymentsFor(sup.id);
                  final filteredPayments = payments.where((p) {
                    switch (period) {
                      case '7D':
                        return p.paidAt.isAfter(DateTime.now().subtract(const Duration(days: 7)));
                      case '30D':
                        return p.paidAt.isAfter(DateTime.now().subtract(const Duration(days: 30)));
                      default:
                        return true;
                    }
                  }).toList();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sup.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${sup.category} · Phone: ${sup.mobile}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Outstanding Due', style: TextStyle(color: AppColors.textLight, fontSize: 11)),
                                Text(
                                  '₹${sup.outstanding.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: sup.outstanding > 0 ? AppColors.nonVegRed : AppColors.vegGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (provider.canManage && sup.outstanding > 0) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.payments_outlined, size: 16),
                              label: const Text('Make Payment'),
                              onPressed: () =>
                                  _showSupplierPaymentDialog(context, provider, sup),
                            ),
                          ),
                        ],
                        if (filteredPayments.isNotEmpty) ...[
                          const Divider(height: 18, color: AppColors.borderLight),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Payment history',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final p in ['All', '7D', '30D'])
                                    ChoiceChip(
                                      label: Text(p),
                                      selected: period == p,
                                      selectedColor: AppColors.primaryGreen,
                                      labelStyle: TextStyle(
                                        color: period == p ? Colors.white : AppColors.textDark,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 10,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (_) => setTabState(() => period = p),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ...filteredPayments.map((p) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.check_circle_outline,
                                    size: 18, color: AppColors.vegGreen),
                                title: Text(
                                  '₹${p.amount.toStringAsFixed(0)} · ${p.method}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${DateFormat('dd MMM yyyy, hh:mm a').format(p.paidAt)}'
                                  '${p.reference != null && p.reference!.isNotEmpty ? ' · Ref: ${p.reference}' : ''}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                ),
                              )),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _showSupplierPaymentDialog(BuildContext context, PosProvider provider, Supplier sup) {
    final amountC = TextEditingController(text: sup.outstanding.toStringAsFixed(0));
    final refC = TextEditingController();
    DateTime when = DateTime.now();
    String method = 'Cash';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Pay Supplier — ${sup.name}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Outstanding due: ₹${sup.outstanding.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Payment amount (₹)', prefixIcon: Icon(Icons.currency_rupee)),
                  ),
                  const SizedBox(height: 12),
                  const Text('Method:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Wrap(
                    spacing: 8,
                    children: ['Cash', 'UPI', 'Bank Transfer']
                        .map((m) => ChoiceChip(
                              label: Text(m),
                              selected: method == m,
                              selectedColor: AppColors.primaryGreen,
                              labelStyle: TextStyle(
                                color: method == m ? Colors.white : AppColors.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              onSelected: (_) => setDialogState(() => method = m),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: when,
                        firstDate: now.subtract(const Duration(days: 365)),
                        lastDate: now,
                      );
                      if (picked != null) setDialogState(() => when = picked);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Payment date',
                        prefixIcon: Icon(Icons.event_outlined, size: 18),
                      ),
                      child: Text(
                        DateFormat('dd MMM yyyy').format(when),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refC,
                    decoration: const InputDecoration(labelText: 'Reference (UPI/Txn no., optional)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountC.text) ?? 0;
                if (amount <= 0) return;
                final ok = await showConfirmDialog(
                  context,
                  title: 'Pay supplier?',
                  message:
                      'Pay ₹${amount.toStringAsFixed(0)} to ${sup.name} ($method)? Remaining due will be updated immediately.',
                  confirmLabel: 'Pay ₹${amount.toStringAsFixed(0)}',
                );
                if (!ok || !context.mounted) return;
                final applied = provider.paySupplier(
                  supplierId: sup.id,
                  amount: amount,
                  method: method,
                  at: when,
                  reference: refC.text.trim().isEmpty ? null : refC.text.trim(),
                );
                if (!context.mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(applied
                        ? '✓ Paid ₹${amount.toStringAsFixed(0)} to ${sup.name}. Remaining due ₹${sup.outstanding.toStringAsFixed(0)}'
                        : 'Payment exceeds the outstanding due (₹${sup.outstanding.toStringAsFixed(0)})'),
                    backgroundColor: applied ? AppColors.vegGreen : AppColors.nonVegRed,
                  ),
                );
              },
              child: const Text('Pay'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSupplierDialog(BuildContext context, PosProvider provider) {
    final nameC = TextEditingController();
    final mobileC = TextEditingController();
    final categoryC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Supplier'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Supplier name')),
              const SizedBox(height: 10),
              TextField(
                controller: mobileC,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Mobile (10-digit)', hintText: '98XXXXXXXX'),
              ),
              const SizedBox(height: 10),
              TextField(controller: categoryC, decoration: const InputDecoration(labelText: 'Category (e.g. Dairy)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameC.text.trim();
              final mobile = mobileC.text.trim();
              final mobileErr = validateMobile(mobile, required: true);
              if (mobileErr != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(mobileErr),
                    backgroundColor: AppColors.nonVegRed,
                  ),
                );
                return;
              }
              if (name.isEmpty) return;
              provider.addSupplier(Supplier(
                id: 'sup-${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                mobile: mobile,
                category: categoryC.text.trim().isEmpty ? 'General' : categoryC.text.trim(),
              ));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✓ Supplier $name added'),
                  backgroundColor: AppColors.vegGreen,
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ---- W5: purchase intake + mark-paid ----

  Widget _buildPurchasesList(BuildContext context, PosProvider provider) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: provider.canManage
          ? FloatingActionButton.extended(
              heroTag: 'addPurchase',
              backgroundColor: AppColors.infoBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.local_shipping_outlined, size: 20),
              label: const Text('Record Purchase'),
              onPressed: () => _showPurchaseDialog(context, provider),
            )
          : null,
      body: provider.purchases.isEmpty
          ? const Center(child: Text('No purchase records yet'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: provider.purchases.length,
              itemBuilder: (context, index) {
                final pur = provider.purchases[index];
                final isPending = pur.paymentStatus == 'Pending';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(pur.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isPending ? AppColors.saffronAmberBg : AppColors.vegGreenBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    pur.paymentStatus,
                                    style: TextStyle(
                                      color: isPending ? AppColors.saffronAmber : AppColors.vegGreen,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${pur.supplierName.isEmpty ? '—' : pur.supplierName} · ₹${pur.totalAmount.toStringAsFixed(0)} · ${DateFormat('dd MMM yyyy').format(pur.date)}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(pur.itemsSummary, style: const TextStyle(color: AppColors.textLight, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      if (isPending && provider.canManage)
                        TextButton(
                          onPressed: () async {
                            final ok = await showConfirmDialog(
                              context,
                              title: 'Mark purchase paid?',
                              message:
                                  'Mark ${pur.invoiceNumber} ₹${pur.totalAmount.toStringAsFixed(0)} as Paid? This clears the supplier due and cannot be undone.',
                              confirmLabel: 'Mark Paid',
                              isDanger: false,
                            );
                            if (!ok || !context.mounted) return;
                            provider.markPurchasePaid(pur.id);
                          },
                          child: const Text('Mark Paid', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _showPurchaseDialog(BuildContext context, PosProvider provider) {
    final invoiceC = TextEditingController();
    final searchC = TextEditingController();
    var supplierId = provider.suppliers.isNotEmpty ? provider.suppliers.first.id : '';
    var status = 'paid';
    DateTime when = DateTime.now();
    final selected = <String, ({double qty, double cost})>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final total = selected.values.fold(0.0, (s, l) => s + l.qty * l.cost);
          final q = searchC.text.trim().toLowerCase();
          // Search-driven: show matches, plus the already-selected lines.
          final visibleItems = provider.inventory.where((item) {
            if (selected.containsKey(item.id)) return true;
            if (q.isEmpty) return false;
            return item.name.toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            title: const Text('Record Purchase'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  TextField(controller: invoiceC, decoration: const InputDecoration(labelText: 'Invoice number')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: supplierId,
                    decoration: const InputDecoration(labelText: 'Supplier (optional)'),
                    items: provider.suppliers
                        .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => supplierId = v ?? ''),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: when,
                        firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => when = picked);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Purchase date',
                        prefixIcon: Icon(Icons.event_outlined, size: 18),
                      ),
                      child: Text(
                        DateFormat('dd MMM yyyy').format(when),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Paid'),
                        selected: status == 'paid',
                        selectedColor: AppColors.vegGreen,
                        onSelected: (_) => setDialogState(() => status = 'paid'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Pending (on credit)'),
                        selected: status == 'pending',
                        selectedColor: AppColors.saffronAmber,
                        onSelected: (_) => setDialogState(() => status = 'pending'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Items received (updates stock):',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 6),
                  // Item search: type to find, then add — no wall of items.
                  TextField(
                    controller: searchC,
                    decoration: InputDecoration(
                      hintText: 'Search item to add…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: searchC.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                searchC.clear();
                                setDialogState(() {});
                              },
                            ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  if (visibleItems.isEmpty)
                    const Text(
                      'Search an inventory item above to add it to this purchase.',
                      style: TextStyle(color: AppColors.textLight, fontSize: 12),
                    )
                  else
                    ...visibleItems.map((item) {
                      final line = selected[item.id];
                      final qtyC = TextEditingController(text: line?.qty.toString() ?? '');
                      final costC = TextEditingController(
                          text: line?.cost.toStringAsFixed(0) ?? item.costPerUnit.toStringAsFixed(0));
                      return Row(
                        children: [
                          Expanded(flex: 2, child: Text(item.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                          Expanded(
                            child: TextField(
                              controller: qtyC,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(hintText: 'qty ${item.unit}', isDense: true),
                              onChanged: (v) => setDialogState(() {
                                final qty = double.tryParse(v) ?? 0;
                                if (qty > 0) {
                                  selected[item.id] = (qty: qty, cost: selected[item.id]?.cost ?? item.costPerUnit);
                                } else {
                                  selected.remove(item.id);
                                }
                              }),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: costC,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '₹/unit', isDense: true),
                              onChanged: (v) => setDialogState(() {
                                final cost = double.tryParse(v) ?? 0;
                                if (selected.containsKey(item.id) && cost >= 0) {
                                  final qty = selected[item.id]!.qty;
                                  selected[item.id] = (qty: qty, cost: cost);
                                }
                              }),
                            ),
                          ),
                        ],
                      );
                    }),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryGreen)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final invoice = invoiceC.text.trim();
                  if (invoice.isEmpty || total <= 0) return;
                  provider.createPurchase(
                    invoiceNo: invoice,
                    supplierId: supplierId,
                    status: status,
                    totalAmount: total,
                    purchasedAt: when,
                    lines: selected.entries.map((e) {
                      final item = provider.inventory.where((i) => i.id == e.key).firstOrNull;
                      return <String, dynamic>{
                        'inventory_item_id': e.key,
                        'name': item?.name ?? '',
                        'qty': e.value.qty,
                        'unit_cost_paise': (e.value.cost * 100).round(),
                      };
                    }).toList(),
                  );
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Purchase $invoice recorded · ₹${total.toStringAsFixed(0)}'),
                      backgroundColor: AppColors.vegGreen,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---- W7: stock adjustment audit log ----

  Widget _buildAdjustmentsLog(BuildContext context, PosProvider provider, List<Map<String, dynamic>> serverLog) {
    final entries = serverLog.isNotEmpty ? serverLog : null;
    return RefreshIndicator(
      onRefresh: () async => _loadServerAdjustments(),
      child: entries == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'This device is offline — showing locally recorded adjustments only.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                ...provider.stockLog.map((s) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${s.itemName}  ${s.change > 0 ? '+' : ''}${s.change.toStringAsFixed(1)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text('${s.reason} · ${s.staffName}', style: const TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.edit_note, color: AppColors.textLight),
                    )),
                if (provider.stockLog.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(child: Text('No stock adjustments recorded yet')),
                  ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final e = entries[index];
                final delta = (e['delta'] as num?)?.toDouble() ?? 0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${e['item_name'] ?? '—'}  ${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${e['reason'] ?? '—'} · ${e['staff_name'] ?? '—'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  leading: Icon(
                    delta >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                    color: delta >= 0 ? AppColors.vegGreen : AppColors.nonVegRed,
                  ),
                );
              },
            ),
    );
  }

  void _showAddItemDialog(BuildContext context, PosProvider provider) {
    final nameC = TextEditingController();
    final unitC = TextEditingController(text: 'KG');
    final stockC = TextEditingController();
    final minC = TextEditingController();
    final costC = TextEditingController();
    final batchC = TextEditingController();
    final rackC = TextEditingController();
    DateTime purchasedAt = DateTime.now();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Inventory Item'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Item name')),
                  const SizedBox(height: 10),
                  TextField(controller: unitC, decoration: const InputDecoration(labelText: 'Unit (KG / Litre / Pcs)')),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: stockC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Opening stock'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: minC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min stock'))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: costC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Cost per unit (₹)'),
                  ),
                  const SizedBox(height: 14),
                  const Text('Purchase details',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: batchC,
                          decoration: const InputDecoration(
                              labelText: 'Batch no.', hintText: 'e.g. B-2409'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: rackC,
                          decoration: const InputDecoration(
                              labelText: 'Storage rack no.', hintText: 'e.g. R-4'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: purchasedAt,
                        firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => purchasedAt = picked);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Purchase date',
                        prefixIcon: Icon(Icons.event_outlined, size: 18),
                      ),
                      child: Text(
                        DateFormat('dd MMM yyyy').format(purchasedAt),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final name = nameC.text.trim();
                final unit = unitC.text.trim();
                final stock = double.tryParse(stockC.text) ?? 0;
                final min = double.tryParse(minC.text) ?? 0;
                final cost = double.tryParse(costC.text) ?? 0;
                if (name.isEmpty || unit.isEmpty) return;
                provider.addInventoryItem(InventoryItem(
                  id: 'inv-${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  availableStock: stock,
                  minStock: min,
                  unit: unit,
                  costPerUnit: cost,
                  batchNo: batchC.text.trim().isEmpty ? null : batchC.text.trim(),
                  rackNo: rackC.text.trim().isEmpty ? null : rackC.text.trim(),
                  purchasedAt: purchasedAt,
                ));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✓ Added $name to inventory'),
                    backgroundColor: AppColors.vegGreen,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

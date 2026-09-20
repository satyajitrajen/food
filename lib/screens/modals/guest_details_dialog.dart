import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/customer_model.dart';
import '../../models/staff_model.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/dialog_controller_scope.dart';

class GuestDetailsDialog extends StatefulWidget {
  final VoidCallback onStartOrder;

  const GuestDetailsDialog({super.key, required this.onStartOrder});

  static void show(BuildContext context, {required VoidCallback onStartOrder}) {
    showDialog(
      context: context,
      builder: (ctx) => GuestDetailsDialog(onStartOrder: onStartOrder),
    );
  }

  @override
  State<GuestDetailsDialog> createState() => _GuestDetailsDialogState();
}

class _GuestDetailsDialogState extends State<GuestDetailsDialog> {
  int _guestCount = 2;
  late TextEditingController _customerController;
  late TextEditingController _phoneController;
  late TextEditingController _notesController;
  String _selectedWaiter = '';

  @override
  void initState() {
    super.initState();
    final provider = context.read<PosProvider>();
    final me = provider.currentStaff;
    _guestCount = provider.selectedTable?.guestCount ?? 2;
    if (_guestCount <= 0) _guestCount = 2;
    _selectedWaiter = me != null && me.role == StaffRole.waiter
        ? me.name
        : provider.selectedTable?.assignedWaiter ?? me?.name ?? '';
    _customerController = TextEditingController(text: provider.activeOrder?.customerName ?? '');
    _phoneController = TextEditingController(text: provider.activeOrder?.customerPhone ?? '');
    _notesController = TextEditingController(text: provider.activeOrder?.orderNote ?? '');
  }

  @override
  void dispose() {
    _customerController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Lets the waiter onboard a table from the customer directory: choosing an
  /// existing customer fills the name + phone so billing can send the receipt.
  Future<void> _pickExistingCustomer(BuildContext context, PosProvider provider) async {
    final queryC = TextEditingController();
    final selected = await showDialog<Customer>(
      context: context,
      builder: (ctx) => DialogControllerScope(
        controllers: [queryC],
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Select Existing Customer'),
          content: SizedBox(
            width: 480,
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: queryC,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Search by name or mobile number',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: provider.customers.length,
                    itemBuilder: (context, i) {
                      final c = provider.customers[i];
                      final q = queryC.text.trim().toLowerCase();
                      final digitsOnly = q.replaceAll(RegExp(r'\D'), '');
                      final matches = q.isEmpty ||
                          c.name.toLowerCase().contains(q) ||
                          (digitsOnly.isNotEmpty &&
                              c.phone.replaceAll(RegExp(r'\D'), '').contains(digitsOnly));
                      if (!matches) return const SizedBox.shrink();
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline, size: 20),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(c.phone, style: const TextStyle(fontSize: 12)),
                        onTap: () => Navigator.of(ctx).pop(c),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel'))],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _customerController.text = selected.name;
        _phoneController.text = selected.phone;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final me = provider.currentStaff;
    final allWaiters = provider.currentOutletWaiters;
    final waiters = me != null && me.role == StaffRole.waiter
        ? allWaiters.where((s) => s.id == me.id).toList()
        : allWaiters;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SizedBox(
          width: 540,
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
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreenLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.table_restaurant, color: AppColors.primaryGreen, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Guest Details — Table ${provider.selectedTable?.tableNumber ?? "Counter"}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Number of Guests (scroll/selectable)
                const Text('Number of Guests', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _guestCount,
                      isExpanded: true,
                      icon: const Icon(Icons.expand_more, color: AppColors.textMuted),
                      items: [
                        // Always offer 1-20, and never drop an existing larger
                        // party (e.g. a 24-seat banqueting table).
                        for (int i = 1; i <= (_guestCount > 20 ? _guestCount : 20); i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              i == 1 ? '1 Guest' : '$i Guests',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _guestCount = v);
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Customer Name & Phone (stacked full-width for readability)
              const Text('Customer Details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: _customerController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  hintText: 'Optional',
                  prefixIcon: Icon(Icons.person_outline, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  prefixIcon: Icon(Icons.phone_outlined, size: 18),
                ),
              ),
              if (provider.customers.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.person_search_outlined, size: 18),
                    label: const Text('Choose existing customer', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () => _pickExistingCustomer(context, provider),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              const SizedBox(height: 8),
              // Waiter Selector
              const Text('Assigned Waiter / Captain', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: waiters.map((w) {
                  final isSelected = _selectedWaiter == w.name;
                  return ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: AppColors.primaryGreenLight,
                      backgroundImage: NetworkImage(w.avatarUrl),
                      onBackgroundImageError: (_, _) {},
                      radius: 10,
                    ),
                    label: Text(w.name),
                    selected: isSelected,
                    selectedColor: AppColors.primaryGreen,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textDark,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => setState(() => _selectedWaiter = w.name),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Special Note
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Special Request (e.g. Birthday, Anniversary, Window seat)',
                  prefixIcon: Icon(Icons.edit_note, size: 20),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    provider.setGuestDetails(
                      count: _guestCount,
                      customerName: _customerController.text.trim().isNotEmpty ? _customerController.text.trim() : null,
                      customerPhone: _phoneController.text.trim(),
                      waiter: _selectedWaiter,
                    );
                    if (_notesController.text.trim().isNotEmpty) {
                      provider.setOrderNote(_notesController.text.trim());
                    }
                    Navigator.of(context).pop();
                    widget.onStartOrder();
                  },
                  child: const Text('Start Order →', style: TextStyle(fontWeight: FontWeight.w700)),
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

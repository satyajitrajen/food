import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/staff_model.dart';
import '../../providers/pos_provider.dart';

/// W3/B3 (PRD admin capability): staff directory management — add staff,
/// toggle active, change role, reset PIN. Manager/Admin only; the server
/// enforces the role on POST /staff and PATCH /staff/{id}.
class StaffAdminScreen extends StatelessWidget {
  const StaffAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final canManage = provider.canManage;
    final staff = List<Staff>.from(provider.staffList)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Staff Management', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Add Staff',
            icon: const Icon(Icons.person_add_alt),
            onPressed: canManage ? () => _showAddDialog(context, provider) : null,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          if (!canManage)
            Container(
              width: double.infinity,
              color: AppColors.saffronAmberBg,
              padding: const EdgeInsets.all(10),
              child: const Text(
                'Manager/Admin login required to manage staff (view only).',
                style: TextStyle(color: AppColors.saffronAmber, fontWeight: FontWeight.w600, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: staff.length,
              itemBuilder: (context, i) {
                final s = staff[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primaryOrangeLight,
                        child: Text(
                          s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                          style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              '${s.roleTitle}${s.isActive ? '' : ' · Inactive'}',
                              style: TextStyle(
                                color: s.isActive ? AppColors.textMuted : AppColors.nonVegRed,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canManage) ...[
                        DropdownButton<StaffRole>(
                          value: s.role,
                          underline: const SizedBox.shrink(),
                          items: StaffRole.values
                              .map((r) => DropdownMenuItem(value: r, child: Text(r.name, style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (r) {
                            if (r != null && r != s.role) provider.updateStaff(s.id, role: r);
                          },
                        ),
                        IconButton(
                          tooltip: s.isActive ? 'Deactivate' : 'Activate',
                          icon: Icon(
                            s.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                            size: 18,
                            color: s.isActive ? AppColors.nonVegRed : AppColors.vegGreen,
                          ),
                          onPressed: () => provider.updateStaff(s.id, isActive: !s.isActive),
                        ),
                        IconButton(
                          tooltip: 'Reset PIN',
                          icon: const Icon(Icons.pin_outlined, size: 18),
                          onPressed: () => _showPinResetDialog(context, provider, s),
                        ),
                      ],
                    ],
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

  void _showAddDialog(BuildContext context, PosProvider provider) {
    final nameC = TextEditingController();
    final pinC = TextEditingController();
    final mobileC = TextEditingController();
    var role = StaffRole.cashier;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Staff'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pinC,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'Login PIN (4-6 digits)', counterText: ''),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: mobileC, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile (optional)')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<StaffRole>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: StaffRole.values
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                        .toList(),
                    onChanged: (v) => setDialogState(() => role = v ?? role),
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
                final pin = pinC.text.trim();
                if (name.isEmpty || pin.length < 4 || pin.length > 6 || !RegExp(r'^\d+$').hasMatch(pin)) return;
                provider.addStaff(Staff(
                  id: 'st-${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  role: role,
                  pin: pin,
                  avatarUrl: '',
                  mobile: mobileC.text.trim(),
                ));
                Navigator.of(ctx).pop();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPinResetDialog(BuildContext context, PosProvider provider, Staff s) {
    final pinC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset PIN — ${s.name}'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: pinC,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'New PIN (4-6 digits)', counterText: ''),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final pin = pinC.text.trim();
              if (pin.length < 4 || pin.length > 6 || !RegExp(r'^\d+$').hasMatch(pin)) return;
              provider.updateStaff(s.id, pin: pin);
              Navigator.of(ctx).pop();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

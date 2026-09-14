import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/staff_model.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../modals/manager_pin_dialog.dart';

/// W3/B3 (PRD admin capability): staff directory management — add staff,
/// toggle active, change role, reset PIN. Manager/Admin only; the server
/// enforces owner protection + role on POST /staff and PATCH /staff/{id}.
/// Main (owner) admin: editable only by itself, never deactivatable/demotable.
class StaffAdminScreen extends StatelessWidget {
  const StaffAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final canManage = provider.canManage;
    final current = provider.currentStaff;
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
                  final isSelf = current?.id == s.id;
                  final iAmManager = current?.role == StaffRole.manager;
                  final isOwnerRow = s.isProtected;
                  // Owner row: only itself may edit (name/PIN); nobody can
                  // change role/status, nobody else can touch it at all.
                  final ownerBlocked = isOwnerRow && !isSelf;
                  // Manager cannot edit any admin row.
                  final managerBlocked =
                      !isOwnerRow && s.role == StaffRole.admin && iAmManager;
                  final selfRoleBlocked = isSelf;
                  final roleEnabled = canManage &&
                      !ownerBlocked &&
                      !managerBlocked &&
                      !selfRoleBlocked;
                  final statusEnabled = canManage &&
                      !ownerBlocked &&
                      !managerBlocked &&
                      !isSelf;
                  final pinEnabled =
                      canManage && !ownerBlocked && !managerBlocked;

                  String roleTooltip = 'Change role';
                  if (ownerBlocked) {
                    roleTooltip =
                        'Main admin (owner) — only the owner can edit this account';
                  } else if (managerBlocked) {
                    roleTooltip = 'Only admins can edit admin staff';
                  } else if (selfRoleBlocked) {
                    roleTooltip = 'You cannot change your own role';
                  }
                  String statusTooltip = s.isActive ? 'Deactivate' : 'Activate';
                  if (ownerBlocked) {
                    statusTooltip =
                        'Main admin (owner) cannot be deactivated';
                  } else if (managerBlocked) {
                    statusTooltip = 'Only admins can edit admin staff';
                  } else if (isSelf) {
                    statusTooltip = 'You cannot deactivate yourself';
                  }

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
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(s.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14)),
                                  ),
                                  if (isOwnerRow) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.infoBlueBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'OWNER',
                                        style: TextStyle(
                                          color: AppColors.infoBlue,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (isSelf) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.creamSubtle,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'YOU',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                s.role == StaffRole.waiter && s.outletId != null
                                    ? 'Waiter · ${provider.outlets.where((o) => o.id == s.outletId).firstOrNull?.name ?? s.outletId}${s.isActive ? '' : ' · Inactive'}'
                                    : '${s.roleTitle}${s.isActive ? '' : ' · Inactive'}',
                                style: TextStyle(
                                  color: s.isActive ? AppColors.textMuted : AppColors.nonVegRed,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (canManage) ...[
                          Tooltip(
                            message: roleTooltip,
                            child: DropdownButton<StaffRole>(
                              value: s.role,
                              underline: const SizedBox.shrink(),
                              items: StaffRole.values
                                  .map((r) => DropdownMenuItem(
                                      value: r,
                                      child: Text(r.name,
                                          style: const TextStyle(fontSize: 12))))
                                  .toList(),
                              onChanged: roleEnabled
                                  ? (r) {
                                      if (r != null && r != s.role) {
                                        _confirmRoleChange(
                                            context, provider, s, r);
                                      }
                                    }
                                  : null,
                            ),
                          ),
                          IconButton(
                            tooltip: statusTooltip,
                            icon: Icon(
                              s.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                              size: 18,
                              color: statusEnabled
                                  ? (s.isActive
                                      ? AppColors.nonVegRed
                                      : AppColors.vegGreen)
                                  : AppColors.textLight,
                            ),
                            onPressed: statusEnabled
                                ? () => _confirmStatusChange(
                                    context, provider, s)
                                : null,
                          ),
                          IconButton(
                            tooltip: ownerBlocked
                                ? 'Main admin (owner) — only the owner can reset this PIN'
                                : (managerBlocked
                                    ? 'Only admins can reset admin PINs'
                                    : 'Reset PIN'),
                            icon: Icon(Icons.password,
                                size: 18,
                                color: pinEnabled
                                    ? AppColors.primaryOrange
                                    : AppColors.textLight),
                            onPressed: pinEnabled
                                ? () =>
                                    _showPinResetDialog(context, provider, s)
                                : null,
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

  Future<void> _confirmRoleChange(BuildContext context, PosProvider provider,
      Staff s, StaffRole r) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Change role?',
      message:
          'Change ${s.name} from ${s.role.name} to ${r.name}? This changes what they can access immediately.',
      confirmLabel: 'Change Role',
    );
    if (!ok || !context.mounted) return;
    final applied = provider.updateStaff(s.id, role: r);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(applied
            ? '✓ Role updated to ${r.name}'
            : 'Blocked: this change is not allowed (owner/self/admin rule)'),
        backgroundColor:
            applied ? AppColors.vegGreen : AppColors.nonVegRed,
      ),
    );
  }

  Future<void> _confirmStatusChange(
      BuildContext context, PosProvider provider, Staff s) async {
    final toActive = !s.isActive;
    final ok = await showConfirmDialog(
      context,
      title: toActive ? 'Activate staff?' : 'Deactivate staff?',
      message: toActive
          ? 'Activate ${s.name} (${s.roleTitle})? They will be able to log in again.'
          : 'Deactivate ${s.name} (${s.roleTitle})? They will immediately lose login access.',
      confirmLabel: toActive ? 'Activate' : 'Deactivate',
    );
    if (!ok || !context.mounted) return;
    final applied = provider.updateStaff(s.id, isActive: toActive);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(applied
            ? (toActive ? '✓ Staff activated' : '✓ Staff deactivated')
            : 'Blocked: this change is not allowed (owner/self/admin rule)'),
        backgroundColor:
            applied ? AppColors.vegGreen : AppColors.nonVegRed,
      ),
    );
  }

  void _showAddDialog(BuildContext context, PosProvider provider) {
    final nameC = TextEditingController();
    final pinC = TextEditingController();
    final mobileC = TextEditingController();
    var role = StaffRole.cashier;
    var selectedOutletId = provider.currentOutlet.id;

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
                  if (role == StaffRole.waiter) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedOutletId,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Outlet',
                        helperText: 'A waiter is assigned to one specific outlet',
                      ),
                      items: provider.outlets
                          .map((o) => DropdownMenuItem(value: o.id, child: Text(o.name)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedOutletId = v ?? selectedOutletId),
                    ),
                  ],
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
                // Managers cannot create admin staff (server enforces too).
                if (provider.currentStaff?.role == StaffRole.manager &&
                    role == StaffRole.admin) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Only admins can create admin staff'),
                      backgroundColor: AppColors.nonVegRed,
                    ),
                  );
                  return;
                }
                provider.addStaff(Staff(
                  id: 'st-${DateTime.now().millisecondsSinceEpoch}',
                  outletId: role == StaffRole.waiter ? selectedOutletId : null,
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
    final isOwnerTarget = s.isProtected;
    final isSelf = provider.currentStaff?.id == s.id;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset PIN — ${s.name}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isOwnerTarget)
                const Text(
                  'Owner account: PIN changes require owner authorization (your own owner session). Manager approval alone is not sufficient.',
                  style: TextStyle(color: AppColors.nonVegRed, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: pinC,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'New PIN (4-6 digits)', counterText: ''),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final pin = pinC.text.trim();
              if (pin.length < 4 || pin.length > 6 || !RegExp(r'^\d+$').hasMatch(pin)) return;
              // Owner target: only owner-self may proceed (server enforces too).
              if (isOwnerTarget && !isSelf) {
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Blocked: only the owner can reset the owner PIN'),
                      backgroundColor: AppColors.nonVegRed,
                    ),
                  );
                }
                return;
              }
              Navigator.of(ctx).pop();
              final ok = await showConfirmDialog(
                context,
                title: 'Reset PIN?',
                message:
                    'Reset login PIN for ${s.name}? They will need the new PIN to log in.',
                confirmLabel: 'Reset PIN',
              );
              if (!ok || !context.mounted) return;
              // Non-owner targets keep the existing manager gate for accountability.
              if (!isOwnerTarget) {
                final managerPin = await ManagerPinDialog.show(
                  context,
                  title: 'Authorize PIN Reset',
                  description:
                      'Enter a Manager/Admin PIN to authorize resetting ${s.name}\u2019s login PIN.',
                );
                if (managerPin == null || !context.mounted) return;
              }
              final applied = provider.updateStaff(s.id, pin: pin);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(applied
                      ? '✓ PIN reset for ${s.name}'
                      : 'Blocked: PIN reset not allowed for this account'),
                  backgroundColor:
                      applied ? AppColors.vegGreen : AppColors.nonVegRed,
                ),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

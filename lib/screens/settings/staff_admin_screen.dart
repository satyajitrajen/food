import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validation.dart';
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
                          backgroundColor: AppColors.primaryGreenLight,
                          child: Text(
                            s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                            style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w800),
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
                                () {
                                  final outletName = s.outletId == null
                                      ? null
                                      : provider.outlets
                                              .where((o) => o.id == s.outletId)
                                              .firstOrNull
                                              ?.name ??
                                          s.outletId;
                                  final parts = <String>[s.roleTitle];
                                  if (outletName != null) parts.add(outletName);
                                  if (s.mobile.trim().isNotEmpty) {
                                    parts.add(s.mobile.trim());
                                  }
                                  if (!s.isActive) parts.add('Inactive');
                                  return parts.join(' · ');
                                }(),
                                style: TextStyle(
                                  color: s.isActive ? AppColors.textMuted : AppColors.nonVegRed,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (canManage)
                          PopupMenuButton<String>(
                            tooltip: 'Manage staff account',
                            icon: const Icon(Icons.more_vert, size: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (action) {
                              switch (action) {
                                case 'role':
                                  _pickRoleChange(context, provider, s);
                                  break;
                                case 'status':
                                  _confirmStatusChange(context, provider, s);
                                  break;
                                case 'pin':
                                  _showPinResetDialog(context, provider, s);
                                  break;
                                case 'edit':
                                  _showEditDialog(context, provider, s);
                                  break;
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'role',
                                enabled: roleEnabled,
                                child: Row(children: [
                                  const Icon(Icons.swap_horiz, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(roleTooltip)),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'status',
                                enabled: statusEnabled,
                                child: Row(children: [
                                  Icon(
                                    s.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                                    size: 18,
                                    color: s.isActive ? AppColors.nonVegRed : AppColors.vegGreen,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(statusTooltip)),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'pin',
                                enabled: pinEnabled,
                                child: Row(children: [
                                  const Icon(Icons.password, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(ownerBlocked
                                      ? 'Main admin (owner) — only the owner can reset this PIN'
                                      : (managerBlocked
                                          ? 'Only admins can reset admin PINs'
                                          : 'Reset PIN'))),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                enabled: pinEnabled,
                                child: Row(children: [
                                  const Icon(Icons.edit_outlined, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(ownerBlocked
                                      ? 'Main admin (owner) — only the owner can edit this account'
                                      : (managerBlocked
                                          ? 'Only admins can edit admin staff'
                                          : 'Edit name, mobile, role & outlet'))),
                                ]),
                              ),
                            ],
                          ),
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

  /// Role picker (replaces the cramped inline dropdown): same confirmations
  /// and rules as before.
  Future<void> _pickRoleChange(
      BuildContext context, PosProvider provider, Staff s) async {
    final r = await showDialog<StaffRole>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Change role — ${s.name}'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        children: StaffRole.values
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          r == s.role ? Icons.radio_button_checked : Icons.radio_button_off,
                          size: 20,
                          color: AppColors.primaryGreen,
                        ),
                        const SizedBox(width: 12),
                        Text(r.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
    if (r == null || r == s.role || !context.mounted) return;
    await _confirmRoleChange(context, provider, s, r);
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
    // Null = org-wide floater (allowed for admin/manager/cashier).
    // Waiter/kitchen must pick a specific outlet (backend enforces).
    String? selectedOutletId = provider.currentOutlet.id;

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
                  TextField(
                    controller: mobileC,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Mobile (10-digit, optional)',
                        hintText: '98XXXXXXXX'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<StaffRole>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: StaffRole.values
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        role = v;
                        // Default waiter/kitchen to current outlet when switching.
                        if ((role == StaffRole.waiter || role == StaffRole.kitchen) &&
                            selectedOutletId == null &&
                            provider.outlets.isNotEmpty) {
                          selectedOutletId = provider.currentOutlet.id;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  if (role == StaffRole.waiter || role == StaffRole.kitchen)
                    DropdownButtonFormField<String>(
                      initialValue: selectedOutletId,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Outlet *',
                        helperText: 'A waiter or kitchen staff is assigned to one specific outlet',
                      ),
                      items: provider.outlets
                          .map((o) => DropdownMenuItem(value: o.id, child: Text(o.name)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedOutletId = v ?? selectedOutletId),
                      validator: (v) => (v == null || v.isEmpty) ? 'Outlet required' : null,
                    )
                  else
                    DropdownButtonFormField<String?>(
                      initialValue: selectedOutletId,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Outlet',
                        helperText: 'Optional — empty means all outlets (org-wide)',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All outlets (org-wide)'),
                        ),
                        ...provider.outlets.map(
                          (o) => DropdownMenuItem<String?>(value: o.id, child: Text(o.name)),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => selectedOutletId = v),
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
                final mobileErr = validateMobile(mobileC.text);
                if (mobileErr != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(mobileErr),
                      backgroundColor: AppColors.nonVegRed,
                    ),
                  );
                  return;
                }
                if (name.isEmpty || pin.length < 4 || pin.length > 6 || !RegExp(r'^\d+$').hasMatch(pin)) return;
                if ((role == StaffRole.waiter || role == StaffRole.kitchen) &&
                    (selectedOutletId == null || selectedOutletId!.isEmpty)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please assign an outlet for waiter/kitchen staff'),
                      backgroundColor: AppColors.nonVegRed,
                    ),
                  );
                  return;
                }
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
                  outletId: role == StaffRole.waiter || role == StaffRole.kitchen
                      ? selectedOutletId
                      : selectedOutletId,
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

  void _showEditDialog(BuildContext context, PosProvider provider, Staff s) {
    final nameC = TextEditingController(text: s.name);
    final mobileC = TextEditingController(text: s.mobile);
    var role = s.role;
    // Null = org-wide (only meaningful for admin/manager/cashier).
    String? selectedOutletId = s.outletId ?? provider.currentOutlet.id;
    if (role != StaffRole.waiter && role != StaffRole.kitchen) {
      selectedOutletId = s.outletId;
    }

    final isSelf = provider.currentStaff?.id == s.id;
    final iAmManager = provider.currentStaff?.role == StaffRole.manager;
    final isOwnerRow = s.isProtected;
    final ownerBlocked = isOwnerRow && !isSelf;
    final managerBlocked =
        !isOwnerRow && s.role == StaffRole.admin && iAmManager;
    // Name/mobile/outlet editable by manager/admin (self included);
    // role change additionally blocked for self.
    final roleChangeBlocked =
        ownerBlocked || managerBlocked || isSelf;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final needsOutlet =
              role == StaffRole.waiter || role == StaffRole.kitchen;
          return AlertDialog(
            title: Text('Edit — ${s.name}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameC,
                      decoration: const InputDecoration(labelText: 'Full name'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: mobileC,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Mobile (optional)'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<StaffRole>(
                      initialValue: role,
                      decoration: InputDecoration(
                        labelText: 'Role',
                        helperText: roleChangeBlocked
                            ? (isSelf
                                ? 'You cannot change your own role'
                                : 'Role change not allowed for this account')
                            : null,
                      ),
                      items: StaffRole.values
                          .map((r) =>
                              DropdownMenuItem(value: r, child: Text(r.name)))
                          .toList(),
                      onChanged: roleChangeBlocked
                          ? null
                          : (v) {
                              if (v == null) return;
                              setDialogState(() {
                                role = v;
                                if ((role == StaffRole.waiter ||
                                        role == StaffRole.kitchen) &&
                                    (selectedOutletId == null ||
                                        selectedOutletId!.isEmpty) &&
                                    provider.outlets.isNotEmpty) {
                                  selectedOutletId =
                                      provider.currentOutlet.id;
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    if (needsOutlet)
                      DropdownButtonFormField<String>(
                        initialValue: selectedOutletId,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Outlet *',
                          helperText:
                              'A waiter or kitchen staff works at one specific outlet',
                        ),
                        items: provider.outlets
                            .map((o) => DropdownMenuItem(
                                value: o.id, child: Text(o.name)))
                            .toList(),
                        onChanged: (v) => setDialogState(
                            () => selectedOutletId = v ?? selectedOutletId),
                      )
                    else
                      DropdownButtonFormField<String?>(
                        initialValue: selectedOutletId,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Outlet',
                          helperText:
                              'Optional — empty means all outlets (org-wide)',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All outlets (org-wide)'),
                          ),
                          ...provider.outlets.map(
                            (o) => DropdownMenuItem<String?>(
                                value: o.id, child: Text(o.name)),
                          ),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => selectedOutletId = v),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final name = nameC.text.trim();
                  final mobile = mobileC.text.trim();
                  final mobileErr = validateMobile(mobile);
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
                  if (needsOutlet &&
                      (selectedOutletId == null ||
                          selectedOutletId!.isEmpty)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Please assign an outlet for waiter/kitchen staff'),
                        backgroundColor: AppColors.nonVegRed,
                      ),
                    );
                    return;
                  }
                  // Managers cannot promote to admin (server enforces too).
                  if (iAmManager &&
                      role == StaffRole.admin &&
                      s.role != StaffRole.admin) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Only admins can create admin staff'),
                        backgroundColor: AppColors.nonVegRed,
                      ),
                    );
                    return;
                  }
                  final roleChanged = role != s.role;
                  final nameChanged = name != s.name;
                  final mobileChanged = mobile != s.mobile;
                  // '' = clear to org-wide; omit when unchanged for others.
                  String? outletParam;
                  if (needsOutlet) {
                    outletParam = (selectedOutletId != s.outletId ||
                            roleChanged)
                        ? selectedOutletId
                        : null;
                  } else {
                    final prev = s.outletId;
                    if (selectedOutletId != prev) {
                      outletParam = selectedOutletId ?? '';
                    }
                  }
                  final applied = provider.updateStaff(
                    s.id,
                    name: nameChanged ? name : null,
                    mobile: mobileChanged ? mobile : null,
                    role: (!roleChangeBlocked && roleChanged) ? role : null,
                    outletId: outletParam,
                  );
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(applied
                          ? '✓ Staff updated'
                          : 'Blocked: this change is not allowed (owner/self/admin rule)'),
                      backgroundColor: applied
                          ? AppColors.vegGreen
                          : AppColors.nonVegRed,
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

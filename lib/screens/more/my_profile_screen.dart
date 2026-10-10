import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/dialog_controller_scope.dart';
import '../../widgets/staff_avatar.dart';
import '../auth/pin_login_screen.dart';
import '../modals/offline_sync_dialog.dart';
import 'attendance_screen.dart';

/// The signed-in staff member's own page: photo, name and mobile, PIN change,
/// today's attendance, this terminal's sync status, and sign out.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  bool _uploading = false;

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.danger : AppColors.success,
    ));
  }

  Future<void> _changePhoto(PosProvider provider) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final lower = picked.name.toLowerCase();
      final mime = picked.mimeType ??
          (lower.endsWith('.png') ? 'image/png' : lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
      final url = await provider.uploadMyAvatar(bytes, filename: picked.name, contentType: mime);
      final err = await provider.updateMyProfile(avatarUrl: url);
      if (!mounted) return;
      _toast(err ?? 'Photo updated', error: err != null);
    } on ApiException catch (e) {
      if (mounted) _toast('Upload failed: ${e.message}', error: true);
    } on NetworkException {
      if (mounted) _toast('You are offline. Try again when connected.', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto(PosProvider provider) async {
    final err = await provider.updateMyProfile(avatarUrl: '');
    if (mounted) _toast(err ?? 'Photo removed', error: err != null);
  }

  Future<void> _editDetails(PosProvider provider) async {
    final me = provider.currentStaff!;
    final nameC = TextEditingController(text: me.name);
    final mobileC = TextEditingController(text: me.mobile);
    String? nameErr;
    String? mobileErr;
    var saving = false;
    await showDialog<void>(
      context: context,
      // The scope disposes the controllers once the dialog is really gone
      // (not when showDialog returns, mid exit-animation).
      builder: (ctx) => DialogControllerScope(
        controllers: [nameC, mobileC],
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit my details'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameC,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: 'Name', errorText: nameErr),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mobileC,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  decoration: InputDecoration(labelText: 'Mobile', prefixText: '+91 ', errorText: mobileErr),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameC.text.trim();
                      final mobile = mobileC.text.trim();
                      setLocal(() {
                        nameErr = name.isEmpty ? 'Enter your name' : null;
                        mobileErr = mobile.isNotEmpty && mobile.length != 10 ? 'Enter a 10-digit mobile' : null;
                      });
                      if (nameErr != null || mobileErr != null) return;
                      setLocal(() => saving = true);
                      final err = await provider.updateMyProfile(name: name, mobile: mobile);
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setLocal(() {
                          saving = false;
                          nameErr = err;
                        });
                        return;
                      }
                      Navigator.of(ctx).pop();
                      _toast('Details saved');
                    },
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePin(PosProvider provider) async {
    final currentC = TextEditingController();
    final newC = TextEditingController();
    final confirmC = TextEditingController();
    String? err;
    var saving = false;
    InputDecoration pinField(String label) => InputDecoration(labelText: label, counterText: '');
    final digits = [FilteringTextInputFormatter.digitsOnly];
    await showDialog<void>(
      context: context,
      builder: (ctx) => DialogControllerScope(
        controllers: [currentC, newC, confirmC],
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Change my PIN'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentC,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: digits,
                  decoration: pinField('Current PIN'),
                ),
                TextField(
                  controller: newC,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: digits,
                  decoration: pinField('New PIN (4-6 digits)'),
                ),
                TextField(
                  controller: confirmC,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: digits,
                  decoration: pinField('Confirm new PIN'),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(err!, style: const TextStyle(color: AppColors.danger)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final current = currentC.text;
                      final next = newC.text;
                      String? problem;
                      if (current.length < 4) {
                        problem = 'Enter your current PIN';
                      } else if (next.length < 4) {
                        problem = 'New PIN must be 4-6 digits';
                      } else if (next != confirmC.text) {
                        problem = 'New PINs do not match';
                      } else if (next == current) {
                        problem = 'New PIN must be different';
                      }
                      if (problem != null) {
                        setLocal(() => err = problem);
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        err = null;
                      });
                      final result = await provider.changeMyPin(current, next);
                      if (!ctx.mounted) return;
                      if (result != null) {
                        setLocal(() {
                          saving = false;
                          err = result;
                        });
                        return;
                      }
                      Navigator.of(ctx).pop();
                      _toast('PIN changed. Use the new PIN next time you sign in.');
                    },
              child: Text(saving ? 'Saving…' : 'Change PIN'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final me = provider.currentStaff;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My profile')),
        body: const Center(child: Text('Not signed in')),
      );
    }
    final today = DateTime.now();
    final todayEntries = provider.attendanceLog
        .where((a) =>
            a.staffId == me.id &&
            a.clockIn.year == today.year &&
            a.clockIn.month == today.month &&
            a.clockIn.day == today.day)
        .toList();
    final minutesToday = todayEntries.fold<int>(0, (s, a) => s + a.minutesWorked);
    final firstIn = todayEntries.isEmpty
        ? null
        : todayEntries.map((a) => a.clockIn).reduce((a, b) => a.isBefore(b) ? a : b);

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
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
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          StaffAvatar(
                            name: me.name,
                            avatarUrl: me.avatarUrl,
                            apiBase: provider.apiBaseUrl,
                            radius: 44,
                          ),
                          Positioned(
                            right: -6,
                            bottom: -6,
                            child: Material(
                            color: AppColors.primaryGreen,
                            shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
                            child: IconButton(
                              tooltip: 'Change photo',
                              iconSize: 16,
                              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                              padding: EdgeInsets.zero,
                              color: Colors.white,
                              onPressed: _uploading ? null : () => _changePhoto(provider),
                              icon: _uploading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.photo_camera_outlined),
                            ),
                          ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(me.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                      const SizedBox(height: 6),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          Chip(label: Text(me.roleTitle)),
                          Chip(
                            avatar: const Icon(Icons.storefront_outlined, size: 16),
                            label: Text(me.outletId == null ? 'All outlets' : provider.currentOutlet.name),
                          ),
                        ],
                      ),
                      if (me.avatarUrl.isNotEmpty)
                        TextButton(
                          onPressed: _uploading ? null : () => _removePhoto(provider),
                          child: const Text('Remove photo'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section('My details'),
                _card(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: const Text('Name'),
                        subtitle: Text(me.name),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: const Text('Mobile'),
                        subtitle: Text(me.mobile.isEmpty ? 'Not added' : '+91 ${me.mobile}'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text('Edit my details'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editDetails(provider),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section('Security'),
                _card(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.pin_outlined),
                        title: const Text('Change my PIN'),
                        subtitle: const Text('4-6 digits, used to sign in on any terminal'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _changePin(provider),
                      ),
                      const Divider(height: 1),
                      const ListTile(
                        leading: Icon(Icons.admin_panel_settings_outlined),
                        title: Text('Role & outlet'),
                        subtitle: Text('Ask a manager to change your role or outlet.'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section('Today'),
                _card(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.login_outlined),
                        title: const Text('Clocked in'),
                        subtitle: Text(firstIn == null ? 'No clock-in on this terminal yet' : formatTime(firstIn)),
                        trailing: Text(
                          '${minutesToday ~/ 60}h ${minutesToday % 60}m',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Attendance log'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const AttendanceScreen())),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section('This terminal'),
                _card(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(provider.currentOutlet.name),
                        subtitle: Text(provider.currentOutlet.terminal.isEmpty
                            ? 'Terminal'
                            : 'Terminal ${provider.currentOutlet.terminal}'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          provider.isOfflineMode ? Icons.cloud_off : Icons.cloud_done_outlined,
                          color: provider.isOfflineMode ? AppColors.warning : AppColors.success,
                        ),
                        title: const Text('Sync status'),
                        subtitle: Text(provider.isOfflineMode
                            ? 'Offline · ${provider.pendingSyncCount} change(s) waiting'
                            : provider.pendingSyncCount > 0
                                ? '${provider.pendingSyncCount} change(s) syncing'
                                : 'All changes synced'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => OfflineSyncDialog.show(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    onPressed: () {
                      provider.logout();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const PinLoginScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                color: AppColors.textMuted, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.6)),
      );

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.creamCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: child,
      );
}

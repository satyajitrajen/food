import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/media.dart';
import '../../core/payments/upi_qr.dart';
import '../../core/theme/app_theme.dart';
import '../../models/settings_model.dart';
import '../../models/table_model.dart';
import '../../providers/pos_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final settings = provider.settings;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('POS System Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Restaurant Profile Card
            _buildSettingsSection(
              title: 'Restaurant Profile',
              subtitle: 'Name, GSTIN, FSSAI, Address & Branding',
              icon: Icons.storefront_outlined,
              trailing: provider.canManage
                  ? IconButton(
                      tooltip: 'Edit profile',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showEditProfileDialog(context, provider, settings),
                    )
                  : null,
              children: [
                _buildSettingItem('Restaurant Name', settings.restaurantName),
                _buildSettingItem('Address', settings.address),
                _buildSettingItem('GSTIN', settings.gstin),
                _buildSettingItem('FSSAI License', settings.fssai),
                _buildSettingItem('Phone / Support', settings.phone),
              ],
            ),
            const SizedBox(height: 16),

            // Taxes & Billing Charges
            _buildSettingsSection(
              title: 'Taxes & Additional Charges',
              subtitle: 'GST rates, Service charges, Delivery & Packaging fees',
              icon: Icons.calculate_outlined,
              children: [
                _buildSettingItem(
                  'GST Rate',
                  settings.isGstInclusive
                      ? '${settings.gstPercentage}% Inclusive of GST (CGST ${(settings.gstPercentage / 2).toStringAsFixed(1)}% + SGST ${(settings.gstPercentage / 2).toStringAsFixed(1)}%)'
                      : '${settings.gstPercentage}% Exclusive (CGST ${(settings.gstPercentage / 2).toStringAsFixed(1)}% + SGST ${(settings.gstPercentage / 2).toStringAsFixed(1)}%)',
                ),
                _buildSettingItem('Menu Pricing', settings.isGstInclusive ? 'Inclusive of GST' : 'Exclusive of GST (+5%)'),
                _buildSettingItem('Service Charge', '${settings.defaultServiceChargePercent}% (Dine-In Optional)'),
                _buildSettingItem('Parcel Packaging', '₹${settings.defaultPackagingCharge.toStringAsFixed(0)} per takeaway bill'),
                _buildSettingItem('Delivery Charge', '₹${settings.defaultDeliveryCharge.toStringAsFixed(0)} flat rate'),
              ],
            ),
            const SizedBox(height: 16),

            // UPI QR customer payments
            _buildUpiCard(context, provider),
            const SizedBox(height: 16),

            // Printer Configuration
            _buildSettingsSection(
              title: 'Thermal Printers Configuration',
              subtitle: 'Hardware mapping for Billing, Kitchen KOT, and Bar stations',
              icon: Icons.print_outlined,
              children: [
                _buildSettingItem('Billing Counter Printer', settings.billingPrinter),
                _buildSettingItem('Kitchen KOT Printer', settings.kitchenPrinter),
                _buildSettingItem('Bar Station Printer', settings.barPrinter),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-print KOT on order placement', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  value: settings.autoPrintKOT,
                  activeThumbColor: AppColors.primaryOrange,
                  onChanged: (v) {
                    provider.updateSettings(settings.copyWith(autoPrintKOT: v));
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow reprint of completed bills', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  value: settings.allowReprint,
                  activeThumbColor: AppColors.primaryOrange,
                  onChanged: (v) {
                    provider.updateSettings(settings.copyWith(allowReprint: v));
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Sections & Tables Configuration
            _buildSectionsCard(context, provider),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionsCard(BuildContext context, PosProvider provider) {
    final sections = provider.diningSections;
    final canManage = provider.canManage;

    return _buildSettingsSection(
      title: 'Dining Sections & Tables',
      subtitle: 'Sections (Garden / AC Dining / Bar), tables & seating',
      icon: Icons.table_bar_outlined,
      children: [
        _buildSettingItem('Configured Sections', sections.join(' · ')),
        _buildSettingItem(
          'Total Tables',
          '${provider.tables.length} Tables (${provider.tables.fold<int>(0, (s, t) => s + t.seats)} Total Seats)',
        ),
        if (canManage) ...[
          const Divider(height: 20, color: AppColors.borderLight),
          const Text('Sections', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sections.map((name) {
              final tableCount = provider.tables.where((t) => t.floor == name).length;
              return InputChip(
                label: Text('$name ($tableCount)'),
                selected: true,
                selectedColor: AppColors.primaryOrangeLight,
                deleteIconColor: AppColors.nonVegRed,
                onPressed: () => _showRenameSectionDialog(context, provider, name),
                onDeleted: () => _deleteSection(context, provider, name),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Section', style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => _showAddSectionDialog(context, provider),
          ),
          const Divider(height: 20, color: AppColors.borderLight),
          const Text('Move Table to Section', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 6),
          for (final t in provider.tables) _buildTableSectionRow(provider, t, sections),
          const Divider(height: 20, color: AppColors.borderLight),
        ],
        TextButton.icon(
          icon: const Icon(Icons.table_restaurant, size: 18),
          label: const Text('Add Table', style: TextStyle(fontWeight: FontWeight.w700)),
          onPressed: canManage ? () => _showAddTableDialog(context, provider, sections) : null,
        ),
      ],
    );
  }

  Widget _buildTableSectionRow(PosProvider provider, RestaurantTable t, List<String> sections) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.creamSubtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(t.tableNumber, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 6),
          Text('${t.seats} seats', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const Spacer(),
          DropdownButton<String>(
            value: sections.contains(t.floor) ? t.floor : null,
            underline: const SizedBox.shrink(),
            isDense: true,
            hint: Text(t.floor, style: const TextStyle(fontSize: 12)),
            items: sections
                .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (s) {
              if (s != null && s != t.floor) provider.updateTableSection(t.id, s);
            },
          ),
        ],
      ),
    );
  }

  // ---- Dialogs ----

  void _showEditProfileDialog(BuildContext context, PosProvider provider, RestaurantSettings settings) {
    final nameC = TextEditingController(text: settings.restaurantName);
    final addressC = TextEditingController(text: settings.address);
    final phoneC = TextEditingController(text: settings.phone);
    final gstinC = TextEditingController(text: settings.gstin);
    final fssaiC = TextEditingController(text: settings.fssai);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Restaurant Profile'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Restaurant name')),
                const SizedBox(height: 10),
                TextField(controller: addressC, decoration: const InputDecoration(labelText: 'Address')),
                const SizedBox(height: 10),
                TextField(controller: phoneC, decoration: const InputDecoration(labelText: 'Phone / Support')),
                const SizedBox(height: 10),
                TextField(controller: gstinC, decoration: const InputDecoration(labelText: 'GSTIN')),
                const SizedBox(height: 10),
                TextField(controller: fssaiC, decoration: const InputDecoration(labelText: 'FSSAI License')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              provider.updateSettings(settings.copyWith(
                restaurantName: nameC.text.trim(),
                address: addressC.text.trim(),
                phone: phoneC.text.trim(),
                gstin: gstinC.text.trim(),
                fssai: fssaiC.text.trim(),
              ));
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildUpiCard(BuildContext context, PosProvider provider) {
    final settings = provider.settings;
    final upiId = validateUpiId(settings.upiId);
    final overrideUrl =
        resolveMediaUrl(settings.upiQrImage, apiBase: provider.apiBaseUrl);
    final configured = upiId != null || overrideUrl.isNotEmpty;

    Widget preview;
    if (overrideUrl.isNotEmpty) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          overrideUrl,
          width: 150,
          height: 150,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _qrIcon(150),
        ),
      );
    } else if (upiId != null) {
      preview = Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderMedium),
        ),
        child: QrImageView(
          data: buildUpiUri(upiId, payeeName: settings.upiName.isEmpty ? null : settings.upiName),
          version: QrVersions.auto,
          size: 140,
        ),
      );
    } else {
      preview = _qrIcon(150);
    }

    return _buildSettingsSection(
      title: 'UPI QR Payments',
      subtitle: 'Customer scan-to-pay QR shown at billing',
      icon: Icons.qr_code_2,
      trailing: provider.canManage
          ? IconButton(
              tooltip: 'Configure UPI QR',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showUpiSettingsDialog(context, provider),
            )
          : null,
      children: [
        _buildSettingItem('UPI ID', configured ? (upiId ?? 'Uploaded QR') : 'Not configured'),
        _buildSettingItem('Payee Name', settings.upiName.isEmpty ? '—' : settings.upiName),
        const SizedBox(height: 10),
        Center(child: preview),
        const SizedBox(height: 8),
        const Text(
          'The QR shown on the payment screen is generated per bill and already '
          'includes the amount, payee and order number.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _qrIcon(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.creamSubtle,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.qr_code_2, color: AppColors.textLight, size: 48),
      );

  Future<void> _showUpiSettingsDialog(BuildContext context, PosProvider provider) async {
    final settings = provider.settings;
    final idC = TextEditingController(text: settings.upiId);
    final nameC = TextEditingController(text: settings.upiName);
    Uint8List? pickedBytes;
    var pickedName = '';
    var pickedMime = '';
    var saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final upiId = validateUpiId(idC.text);
          final overrideUrl =
              resolveMediaUrl(settings.upiQrImage, apiBase: provider.apiBaseUrl);

          Future<void> pickImage() async {
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1200,
              maxHeight: 1200,
            );
            if (picked == null || !ctx.mounted) return;
            final bytes = await picked.readAsBytes();
            setDialogState(() {
              pickedBytes = bytes;
              pickedName = picked.name;
              pickedMime = (picked.mimeType != null && picked.mimeType!.isNotEmpty)
                  ? picked.mimeType!
                  : (pickedName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
            });
          }

          Future<void> save() async {
            if (saving) return;
            setDialogState(() => saving = true);
            var qrImage = settings.upiQrImage;
            if (pickedBytes != null) {
              try {
                qrImage = await provider.uploadSettingsImage(
                  pickedBytes!,
                  filename: pickedName.isEmpty ? 'upi-qr.png' : pickedName,
                  contentType: pickedMime.isEmpty ? 'image/png' : pickedMime,
                );
              } on ApiException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Upload failed: ${e.message}')));
                }
                setDialogState(() => saving = false);
                return;
              } on NetworkException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Upload failed (offline): ${e.message}')));
                }
                setDialogState(() => saving = false);
                return;
              }
            }
            provider.updateSettings(settings.copyWith(
              upiId: idC.text.trim(),
              upiName: nameC.text.trim(),
              upiQrImage: qrImage,
            ));
            if (ctx.mounted) Navigator.of(ctx).pop();
          }

          return AlertDialog(
            title: const Text('UPI QR Configuration'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderMedium),
                        ),
                        child: pickedBytes != null
                            ? Image.memory(pickedBytes!, width: 150, height: 150, fit: BoxFit.contain)
                            : overrideUrl.isNotEmpty
                                ? Image.network(overrideUrl,
                                    width: 150, height: 150, fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) => _qrIcon(150))
                                : upiId != null
                                    ? QrImageView(
                                        data: buildUpiUri(upiId, payeeName: nameC.text.trim().isEmpty ? null : nameC.text.trim()),
                                        version: QrVersions.auto,
                                        size: 150)
                                    : _qrIcon(150),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: idC,
                      decoration: const InputDecoration(
                        labelText: 'UPI ID',
                        hintText: 'e.g. spicehaven@okhdfcbank',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameC,
                      decoration: const InputDecoration(labelText: 'Payee name (shown under the QR)'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: saving ? null : pickImage,
                          icon: const Icon(Icons.image_outlined, size: 16),
                          label: const Text('Upload QR image (optional)'),
                        ),
                        if (settings.upiQrImage.isNotEmpty || pickedBytes != null)
                          TextButton.icon(
                            onPressed: saving
                                ? null
                                : () => setDialogState(() {
                                      pickedBytes = null;
                                      pickedName = '';
                                    }),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Clear uploaded image'),
                          ),
                      ],
                    ),
                    const Text(
                      'Prefer entering the UPI ID: the bill QR is generated fresh '
                      'with the amount. Upload only if you must use a bank-branded QR.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: saving ? null : save,
                child: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    idC.dispose();
    nameC.dispose();
  }

  /// Sections to edit against: the configured list when present, otherwise
  /// the floors in use by tables (legacy/empty-config) materialized into a
  /// fresh mutable copy so partial edits never drop other sections.
  List<String> _sectionBase(PosProvider provider) {
    final configured = provider.settings.sections;
    return List<String>.from(
      configured.isNotEmpty ? configured : provider.diningSections,
    );
  }

  void _showAddSectionDialog(BuildContext context, PosProvider provider) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Dining Section'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Section name (e.g. Garden, AC Dining, Bar)'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = c.text.trim();
              final base = _sectionBase(provider);
              if (name.isNotEmpty && !base.contains(name)) {
                provider.updateSettings(
                  provider.settings.copyWith(sections: [...base, name]),
                );
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showRenameSectionDialog(BuildContext context, PosProvider provider, String oldName) {
    final c = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename Section — $oldName'),
        content: SizedBox(
          width: 420,
          child: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'New section name')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final newName = c.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                // Re-home every table sitting in this section first.
                for (final t in provider.tables.where((t) => t.floor == oldName)) {
                  provider.updateTableSection(t.id, newName);
                }
                final list = _sectionBase(provider);
                final idx = list.indexOf(oldName);
                if (idx >= 0) {
                  list[idx] = newName;
                } else {
                  list.add(newName); // renamed a floor-derived section
                }
                provider.updateSettings(provider.settings.copyWith(sections: list));
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _deleteSection(BuildContext context, PosProvider provider, String name) {
    final used = provider.tables.where((t) => t.floor == name).length;
    if (used > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot delete "$name": $used table(s) are in it. Move them first.')),
      );
      return;
    }
    final next = _sectionBase(provider).where((s) => s != name).toList();
    if (next.length == provider.settings.sections.length &&
        !provider.settings.sections.contains(name)) {
      return; // nothing configured changed
    }
    provider.updateSettings(provider.settings.copyWith(sections: next));
  }

  void _showAddTableDialog(BuildContext context, PosProvider provider, List<String> sections) {
    final numC = TextEditingController();
    final seatsC = TextEditingController();
    var floor = sections.isNotEmpty ? sections.first : 'Ground Floor';
    var creatingNew = false;
    final newFloorC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Table'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: numC, decoration: const InputDecoration(labelText: 'Table number (e.g. T13)')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: seatsC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Seats'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: floor,
                    decoration: const InputDecoration(labelText: 'Section'),
                    items: [
                      ...sections.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                      const DropdownMenuItem(value: '__new__', child: Text('+ New section…')),
                    ],
                    onChanged: (v) => setDialogState(() {
                      creatingNew = v == '__new__';
                      if (!creatingNew && v != null) floor = v;
                    }),
                  ),
                  if (creatingNew) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: newFloorC,
                      decoration: const InputDecoration(labelText: 'New section name'),
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
                final num = numC.text.trim();
                final seats = int.tryParse(seatsC.text.trim()) ?? 0;
                var section = floor;
                if (creatingNew) {
                  section = newFloorC.text.trim();
                  final base = _sectionBase(provider);
                  if (section.isNotEmpty && !base.contains(section)) {
                    provider.updateSettings(
                      provider.settings.copyWith(sections: [...base, section]),
                    );
                  }
                }
                if (num.isEmpty || seats <= 0 || section.isEmpty) return;
                provider.addTable(tableNumber: num, seats: seats, floor: section);
                Navigator.of(ctx).pop();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryOrangeLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primaryOrange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const Divider(height: 24, color: AppColors.borderLight),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

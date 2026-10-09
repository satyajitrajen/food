import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/media.dart';
import '../../core/payments/upi_qr.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../models/settings_model.dart';
import '../../models/table_model.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/dialog_controller_scope.dart';
import 'subscription_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final settings = provider.settings;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Settings'),
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

            // Subscription (API terminals, admins only)
            if (provider.apiEnabled && provider.isAdmin) ...[
              _buildSettingsSection(
                title: 'Subscription',
                subtitle: 'Plan, billing & auto-renew',
                icon: Icons.workspace_premium_outlined,
                children: const [SubscriptionCardBody()],
              ),
              const SizedBox(height: 16),
            ],

            // Taxes & Billing Charges
            _buildSettingsSection(
              title: 'Taxes & Additional Charges',
              subtitle: 'GST rates, Service charges & Packaging fees',
              icon: Icons.calculate_outlined,
              trailing: provider.canManage
                  ? IconButton(
                      tooltip: 'Edit taxes & charges',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showEditChargesDialog(context, provider, settings),
                    )
                  : null,
              children: [
                _buildSettingItem(
                  'GST Rate',
                  settings.isGstInclusive
                      ? '${settings.gstPercentage}% Inclusive of GST (CGST ${(settings.gstPercentage / 2).toStringAsFixed(1)}% + SGST ${(settings.gstPercentage / 2).toStringAsFixed(1)}%)'
                      : '${settings.gstPercentage}% Exclusive (CGST ${(settings.gstPercentage / 2).toStringAsFixed(1)}% + SGST ${(settings.gstPercentage / 2).toStringAsFixed(1)}%)',
                ),
                _buildSettingItem('Menu Pricing', settings.isGstInclusive ? 'Inclusive of GST' : 'Exclusive of GST (+${settings.gstPercentage.toStringAsFixed(settings.gstPercentage % 1 == 0 ? 0 : 1)}%)'),
                _buildSettingItem('Service Charge',
                    settings.defaultServiceChargePercent > 0 ? '${settings.defaultServiceChargePercent}% on dine-in' : 'None'),
                _buildSettingItem('Packaging Charge', settings.defaultPackagingCharge > 0
                    ? '${formatInr(settings.defaultPackagingCharge)} per takeaway/delivery order'
                    : 'None'),
                _buildSettingItem('Delivery Charge', settings.defaultDeliveryCharge > 0
                    ? '${formatInr(settings.defaultDeliveryCharge)} per delivery order'
                    : 'None'),
              ],
            ),
            const SizedBox(height: 16),

            // UPI QR customer payments
            _buildUpiCard(context, provider),
            const SizedBox(height: 16),

            // Printer Configuration
            _buildSettingsSection(
              title: 'Thermal Printers',
              subtitle: 'Network (LAN/Wi-Fi) ESC/POS printers as IP:port',
              icon: Icons.print_outlined,
              trailing: provider.canManage
                  ? IconButton(
                      tooltip: 'Edit printers',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showEditPrintersDialog(context, provider, settings),
                    )
                  : null,
              children: [
                _buildSettingItem('Billing printer',
                    settings.billingPrinter.isEmpty ? 'Not set' : settings.billingPrinter),
                _buildSettingItem('Kitchen (KOT) printer',
                    settings.kitchenPrinter.isEmpty ? 'Uses billing printer' : settings.kitchenPrinter),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-print KOT on order placement', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  value: settings.autoPrintKOT,
                  activeThumbColor: AppColors.primaryGreen,
                  onChanged: provider.canManage
                      ? (v) => provider.updateSettings(settings.copyWith(autoPrintKOT: v))
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow reprint of completed bills', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  value: settings.allowReprint,
                  activeThumbColor: AppColors.primaryGreen,
                  onChanged: provider.canManage
                      ? (v) => provider.updateSettings(settings.copyWith(allowReprint: v))
                      : null,
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
                selectedColor: AppColors.primaryGreenLight,
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
          for (final t in provider.tables) _buildTableSectionRow(context, provider, t, sections),
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

  Widget _buildTableSectionRow(BuildContext context, PosProvider provider, RestaurantTable t, List<String> sections) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.creamSubtle,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      t.tableNumber,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('${t.seats} seats', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: sections.contains(t.floor) ? t.floor : null,
            underline: const SizedBox.shrink(),
            isDense: true,
            hint: Text(t.floor, style: const TextStyle(fontSize: 12)),
            items: sections
                .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (s) async {
              if (s != null && s != t.floor) {
                final ok = await showConfirmDialog(
                  context,
                  title: 'Move table?',
                  message:
                      'Move table ${t.tableNumber} from "${t.floor}" to "$s"?',
                  confirmLabel: 'Move Table',
                  isDanger: false,
                );
                if (!ok || !context.mounted) return;
                provider.updateTableSection(t.id, s);
              }
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
    final emailC = TextEditingController(text: settings.email);
    final gstinC = TextEditingController(text: settings.gstin);
    final fssaiC = TextEditingController(text: settings.fssai);
    String? gstinErr;
    String? fssaiErr;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Restaurant profile'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Printed on every bill for this outlet.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 10),
                  TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Name on bills')),
                  const SizedBox(height: 10),
                  TextField(controller: addressC, maxLines: 2, decoration: const InputDecoration(labelText: 'Address')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneC,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailC,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: gstinC,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(labelText: 'GSTIN', errorText: gstinErr),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: fssaiC,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'FSSAI licence no.', errorText: fssaiErr),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final gstin = gstinC.text.trim().toUpperCase();
                final fssai = fssaiC.text.trim();
                setLocal(() {
                  gstinErr = gstin.isEmpty || RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gstin)
                      ? null
                      : 'GSTIN is 15 characters, e.g. 27ABCDE1234F1Z5';
                  fssaiErr = fssai.isEmpty || RegExp(r'^\d{14}$').hasMatch(fssai)
                      ? null
                      : 'FSSAI licence number is 14 digits';
                });
                if (gstinErr != null || fssaiErr != null) return;
                provider.updateOutletProfile(
                  name: nameC.text.trim(),
                  address: addressC.text.trim(),
                  phone: phoneC.text.trim(),
                  email: emailC.text.trim(),
                  gstin: gstin,
                  fssai: fssai,
                );
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditChargesDialog(BuildContext context, PosProvider provider, RestaurantSettings settings) {
    var gst = settings.gstPercentage;
    var inclusive = settings.isGstInclusive;
    final serviceC = TextEditingController(text: rupeeInput(settings.defaultServiceChargePercent));
    final packagingC = TextEditingController(text: rupeeInput(settings.defaultPackagingCharge));
    final deliveryC = TextEditingController(text: rupeeInput(settings.defaultDeliveryCharge));
    String? err;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Taxes & charges'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('GST rate', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final r in const [0.0, 5.0, 12.0, 18.0, 28.0])
                        ChoiceChip(
                          label: Text('${r.toStringAsFixed(0)}%'),
                          selected: gst == r,
                          onSelected: (_) => setLocal(() => gst = r),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Menu prices include GST'),
                    value: inclusive,
                    onChanged: (v) => setLocal(() => inclusive = v),
                  ),
                  TextField(
                    controller: serviceC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Service charge (%) on dine-in', suffixText: '%'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: packagingC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Packaging per takeaway/delivery order', prefixText: '₹ '),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: deliveryC,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Delivery charge per delivery order', prefixText: '₹ '),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Text(err!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 8),
                  const Text('Applies to new orders. Open orders keep their charges.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final service = double.tryParse(serviceC.text.trim()) ?? -1;
                final packaging = double.tryParse(packagingC.text.trim()) ?? -1;
                final delivery = double.tryParse(deliveryC.text.trim()) ?? -1;
                if (service < 0 || service > 20 || packaging < 0 || delivery < 0) {
                  setLocal(() => err = 'Service charge must be 0–20% and charges cannot be negative.');
                  return;
                }
                provider.updateSettings(settings.copyWith(
                  gstPercentage: gst,
                  isGstInclusive: inclusive,
                  defaultServiceChargePercent: service,
                  defaultPackagingCharge: packaging,
                  defaultDeliveryCharge: delivery,
                ));
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPrintersDialog(BuildContext context, PosProvider provider, RestaurantSettings settings) {
    final billingC = TextEditingController(text: settings.billingPrinter);
    final kitchenC = TextEditingController(text: settings.kitchenPrinter);
    String? billingErr;
    String? kitchenErr;
    String? validate(String v) {
      if (v.trim().isEmpty) return null;
      return RegExp(r'^[A-Za-z0-9.\-]+:\d{2,5}$').hasMatch(v.trim()) ? null : 'Use IP:port, e.g. 192.168.1.50:9100';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Printers'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: billingC,
                  decoration: InputDecoration(
                    labelText: 'Billing printer (IP:port)',
                    hintText: '192.168.1.50:9100',
                    errorText: billingErr,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: kitchenC,
                  decoration: InputDecoration(
                    labelText: 'Kitchen KOT printer (optional)',
                    hintText: 'Leave empty to use the billing printer',
                    errorText: kitchenErr,
                  ),
                ),
                const SizedBox(height: 10),
                const Text('Most thermal printers listen on port 9100. Find the IP on the printer\'s self-test slip.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                setLocal(() {
                  billingErr = validate(billingC.text);
                  kitchenErr = validate(kitchenC.text);
                });
                if (billingErr != null || kitchenErr != null) return;
                provider.updateSettings(settings.copyWith(
                  billingPrinter: billingC.text.trim(),
                  kitchenPrinter: kitchenC.text.trim(),
                ));
                Navigator.of(ctx).pop();
                if (billingC.text.trim().isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                final ok = await provider.printTestPage();
                messenger.showSnackBar(SnackBar(
                  content: Text(ok ? 'Saved. Test page printed.' : 'Saved, but test print failed: ${provider.printerError ?? ''}'),
                  backgroundColor: ok ? AppColors.success : AppColors.danger,
                ));
              },
              child: const Text('Save & test print'),
            ),
          ],
        ),
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
      builder: (ctx) => DialogControllerScope(
        controllers: [idC, nameC],
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
                        hintText: 'e.g. yourshop@okhdfcbank',
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

  void _deleteSection(BuildContext context, PosProvider provider, String name) async {
    final used = provider.tables.where((t) => t.floor == name).length;
    if (used > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot delete "$name": $used table(s) are in it. Move them first.')),
      );
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: 'Delete section?',
      message: 'Delete dining section "$name"? This removes it from settings and cannot be undone.',
      confirmLabel: 'Delete Section',
    );
    if (!ok || !context.mounted) return;
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
                  color: AppColors.primaryGreenLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primaryGreen, size: 20),
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

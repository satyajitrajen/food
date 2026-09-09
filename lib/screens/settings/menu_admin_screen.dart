import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/media.dart';
import '../../core/theme/app_theme.dart';
import '../../models/menu_model.dart';
import '../../providers/pos_provider.dart';

/// W2 (FR-M1/M2): menu management for managers/admins — add/edit/delete items,
/// availability toggle, photo upload, and full variant/modifier-group (add-on)
/// editing. Writes go through the sync outbox; the server enforces manager.
class MenuAdminScreen extends StatelessWidget {
  const MenuAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final canManage = provider.canManage;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Menu Management', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Add Menu Item',
            icon: const Icon(Icons.add),
            onPressed: canManage ? () => _showEditDialog(context) : null,
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
                  'Manager/Admin login required to edit the menu (view only).',
                  style: TextStyle(color: AppColors.saffronAmber, fontWeight: FontWeight.w600, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: provider.menuItems.length,
                itemBuilder: (context, i) {
                  final item = provider.menuItems[i];
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
                        Container(
                          width: 6,
                          height: 42,
                          decoration: BoxDecoration(
                            color: item.isVeg ? AppColors.vegGreen : AppColors.nonVegRed,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _itemThumb(context, item),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.name}  ·  ₹${item.price.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (item.category.isNotEmpty) item.category,
                                  if (item.variants.isNotEmpty) '${item.variants.length} variant(s)',
                                  if (item.modifierGroups.isNotEmpty) '${item.modifierGroups.length} add-on set(s)',
                                ].join(' · '),
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: item.isAvailable,
                          activeThumbColor: AppColors.vegGreen,
                          onChanged: canManage
                              ? (v) => provider.updateMenuItem(item, isAvailable: v)
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: canManage ? () => _showEditDialog(context, item) : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.nonVegRed),
                          onPressed: canManage ? () => _confirmDelete(context, provider, item) : null,
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

  Widget _itemThumb(BuildContext context, MenuItem item) {
    final url = resolveMediaUrl(item.imageUrl, apiBase: context.read<PosProvider>().apiBaseUrl);
    if (url.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.creamSubtle, borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.fastfood, size: 18, color: AppColors.textLight),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 40,
          height: 40,
          color: AppColors.creamSubtle,
          child: const Icon(Icons.fastfood, size: 18, color: AppColors.textLight),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, PosProvider provider, MenuItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: const SizedBox(
          width: 440,
          child: Text('The item disappears from the POS menu. Existing past orders keep their data.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              provider.deleteMenuItem(item.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.nonVegRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, [MenuItem? existing]) async {
    final provider = context.read<PosProvider>();
    final nameC = TextEditingController(text: existing?.name ?? '');
    final priceC = TextEditingController(text: existing == null ? '' : existing.price.toStringAsFixed(0));
    final descC = TextEditingController(text: existing?.description ?? '');
    final categories = provider.categories.where((c) => c != 'All').toList();
    var category = existing?.category.isNotEmpty == true ? existing!.category : (categories.isNotEmpty ? categories.first : 'Starters');
    var isVeg = existing?.isVeg ?? true;
    var isBestseller = existing?.isBestseller ?? false;
    // Working copies of add-ons edited via the sub-dialogs.
    var variants = existing?.variants.map((v) => v.copy()).toList() ?? <ProductVariant>[];
    var groups = existing?.modifierGroups.map((g) => g.copy()).toList() ?? <ModifierGroup>[];
    // Photo state.
    Uint8List? pickedBytes;
    var pickedName = '';
    var pickedMime = '';
    var removedImage = false;
    var saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final existingUrl = resolveMediaUrl(
            (removedImage ? '' : existing?.imageUrl ?? ''),
            apiBase: provider.apiBaseUrl,
          );

          Future<void> choosePhoto() async {
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 88,
            );
            if (picked == null) return;
            final bytes = await picked.readAsBytes();
            if (!ctx.mounted) return;
            setDialogState(() {
              pickedBytes = bytes;
              pickedName = picked.name;
              // Prefer the picker's real MIME type; fall back to extension.
              pickedMime = (picked.mimeType != null && picked.mimeType!.isNotEmpty)
                  ? picked.mimeType!
                  : _mimeOf(picked.name);
              removedImage = false;
            });
          }

          Future<void> save() async {
            final name = nameC.text.trim();
            final price = double.tryParse(priceC.text) ?? 0;
            if (name.isEmpty || price <= 0) return;
            setDialogState(() => saving = true);

            var finalImage = removedImage ? '' : (existing?.imageUrl ?? '');
            if (pickedBytes != null) {
              try {
                final imageUrl = await provider.uploadMenuImage(
                  pickedBytes!,
                  filename: pickedName.isEmpty ? 'menu.jpg' : pickedName,
                  contentType: pickedMime.isNotEmpty ? pickedMime : _mimeOf(pickedName),
                );
                if (imageUrl.isNotEmpty) finalImage = imageUrl;
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

            if (existing == null) {
              provider.addMenuItem(MenuItem(
                id: 'm-${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                category: category,
                price: price,
                isVeg: isVeg,
                imageUrl: finalImage,
                description: descC.text.trim(),
                variants: variants,
                modifierGroups: groups,
                isBestseller: isBestseller,
              ));
            } else {
              final updated = existing.copyWith(
                name: name,
                category: category,
                price: price,
                isVeg: isVeg,
                imageUrl: finalImage,
                description: descC.text.trim(),
                variants: variants,
                modifierGroups: groups,
                isBestseller: isBestseller,
              );
              provider.updateMenuItem(
                updated,
                variants: variants,
                modifierGroups: groups,
              );
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
          }

          return AlertDialog(
            title: Text(existing == null ? 'Add Menu Item' : 'Edit ${existing.name}'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Name')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setDialogState(() => category = v ?? category),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Base Price (₹)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descC,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Description (optional)'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Vegetarian', style: TextStyle(fontSize: 14)),
                      value: isVeg,
                      onChanged: (v) => setDialogState(() => isVeg = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bestseller', style: TextStyle(fontSize: 14)),
                      value: isBestseller,
                      onChanged: (v) => setDialogState(() => isBestseller = v),
                    ),

                    // ---- Photo ----
                    const Divider(height: 24, color: AppColors.borderLight),
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 84,
                            height: 84,
                            child: pickedBytes != null
                                ? Image.memory(pickedBytes!, fit: BoxFit.cover)
                                : existingUrl.isNotEmpty
                                    ? Image.network(
                                        existingUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => _emptyPhoto(),
                                      )
                                    : _emptyPhoto(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Menu Photo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(
                                pickedBytes != null
                                    ? 'Photo selected — uploads on save'
                                    : 'Upload a photo of the dish (JPEG/PNG/WebP, ≤5 MB)',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: saving ? null : choosePhoto,
                                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                                    label: Text(pickedBytes != null || existingUrl.isNotEmpty ? 'Change Photo' : 'Choose Photo'),
                                  ),
                                  if (pickedBytes != null || (existing?.imageUrl.isNotEmpty ?? false))
                                    TextButton.icon(
                                      onPressed: saving
                                          ? null
                                          : () => setDialogState(() {
                                                pickedBytes = null;
                                                pickedName = '';
                                                pickedMime = '';
                                                removedImage = true;
                                              }),
                                      icon: const Icon(Icons.delete_outline, size: 16),
                                      label: const Text('Remove'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ---- Variants ----
                    const Divider(height: 24, color: AppColors.borderLight),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Variants (e.g. Half/Full, Regular/Large)',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final result = await _VariantsEditorDialog.show(ctx, variants);
                            if (result != null) setDialogState(() => variants = result);
                          },
                          icon: const Icon(Icons.tune, size: 16),
                          label: Text('Edit (${variants.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    if (variants.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: variants
                                .map((v) => Chip(
                                      label: Text('${v.name} · ₹${v.price.toStringAsFixed(0)}'),
                                      visualDensity: VisualDensity.compact,
                                      labelStyle: const TextStyle(fontSize: 11),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),

                    // ---- Add-on groups ----
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Add-ons (groups of priced options)',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final result = await _ModifierGroupsEditorDialog.show(ctx, groups);
                            if (result != null) setDialogState(() => groups = result);
                          },
                          icon: const Icon(Icons.checklist, size: 16),
                          label: Text('Edit (${groups.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    if (groups.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: groups
                              .map((g) => Chip(
                                    label: Text(
                                      '${g.name}${g.isRequired ? ' (required)' : ''} · ${g.items.length} item(s)',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    labelStyle: const TextStyle(fontSize: 11),
                                  ))
                              .toList(),
                        ),
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
                    : Text(existing == null ? 'Add' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
    nameC.dispose();
    priceC.dispose();
    descC.dispose();
  }

  Widget _emptyPhoto() => Container(
        width: 84,
        height: 84,
        color: AppColors.creamSubtle,
        child: const Icon(Icons.restaurant_menu, color: AppColors.textLight, size: 28),
      );

  static String _mimeOf(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}

// ---------------------------------------------------------------------------
// Variants editor
// ---------------------------------------------------------------------------

class _VariantsEditorDialog extends StatefulWidget {
  final List<ProductVariant> initial;
  const _VariantsEditorDialog({required this.initial});

  static Future<List<ProductVariant>?> show(BuildContext context, List<ProductVariant> initial) {
    return showDialog<List<ProductVariant>>(
      context: context,
      builder: (_) => _VariantsEditorDialog(initial: initial),
    );
  }

  @override
  State<_VariantsEditorDialog> createState() => _VariantsEditorDialogState();
}

class _VariantsEditorDialogState extends State<_VariantsEditorDialog> {
  late final List<_DraftRow> _rows = widget.initial
      .map((v) => _DraftRow(name: v.name, price: v.price))
      .toList();

  @override
  void dispose() {
    for (final r in _rows) {
      r.name.dispose();
      r.price.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Variants'),
      content: SizedBox(
        width: 520,
        height: 380,
        child: ListView(
          children: [
            if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No variants — the base price is used.',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              ),
            for (final row in _rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: row.name,
                        decoration: const InputDecoration(labelText: 'Variant name'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: row.price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Price (₹)'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: AppColors.nonVegRed),
                      onPressed: () => setState(() => _rows.remove(row)),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _rows.add(_DraftRow(name: '', price: null))),
              icon: const Icon(Icons.add),
              label: const Text('Add Variant'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final out = <ProductVariant>[];
            var seq = 0;
            for (final r in _rows) {
              final name = r.name.text.trim();
              if (name.isEmpty) continue;
              out.add(ProductVariant(
                id: 'v-${DateTime.now().millisecondsSinceEpoch}-${seq++}',
                name: name,
                price: double.tryParse(r.price.text) ?? 0,
              ));
            }
            Navigator.of(context).pop(out);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add-on groups editor (modifier groups with priced items)
// ---------------------------------------------------------------------------

class _ModifierGroupsEditorDialog extends StatefulWidget {
  final List<ModifierGroup> initial;
  const _ModifierGroupsEditorDialog({required this.initial});

  static Future<List<ModifierGroup>?> show(BuildContext context, List<ModifierGroup> initial) {
    return showDialog<List<ModifierGroup>>(
      context: context,
      builder: (_) => _ModifierGroupsEditorDialog(initial: initial),
    );
  }

  @override
  State<_ModifierGroupsEditorDialog> createState() => _ModifierGroupsEditorDialogState();
}

class _ModifierGroupsEditorDialogState extends State<_ModifierGroupsEditorDialog> {
  late final List<_GroupDraft> _groups = widget.initial
      .map((g) => _GroupDraft(
            name: g.name,
            multi: g.isMultiSelect,
            required: g.isRequired,
            items: g.items.map((m) => _DraftRow(name: m.name, price: m.price)).toList(),
          ))
      .toList();

  @override
  void dispose() {
    for (final g in _groups) {
      g.name.dispose();
      for (final i in g.items) {
        i.name.dispose();
        i.price.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add-on Groups'),
      content: SizedBox(
        width: 580,
        height: 460,
        child: ListView(
          children: [
            if (_groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No add-on groups defined.',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              ),
            for (var gi = 0; gi < _groups.length; gi++) _groupCard(_groups[gi], gi),
            TextButton.icon(
              onPressed: () => setState(() => _groups.add(_GroupDraft(name: '', multi: true, required: false, items: []))),
              icon: const Icon(Icons.add),
              label: const Text('Add Group'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final out = <ModifierGroup>[];
            var gSeq = 0;
            var iSeq = 0;
            for (final g in _groups) {
              final gName = g.name.text.trim();
              if (gName.isEmpty) continue;
              final items = <ModifierItem>[];
              for (final it in g.items) {
                final name = it.name.text.trim();
                if (name.isEmpty) continue;
                items.add(ModifierItem(
                  id: 'mo-${DateTime.now().millisecondsSinceEpoch}-${iSeq++}',
                  name: name,
                  price: double.tryParse(it.price.text) ?? 0,
                ));
              }
              out.add(ModifierGroup(
                id: 'mg-${DateTime.now().millisecondsSinceEpoch}-${gSeq++}',
                name: gName,
                isMultiSelect: g.multi,
                isRequired: g.required,
                items: items,
              ));
            }
            Navigator.of(context).pop(out);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _groupCard(_GroupDraft g, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: g.name,
                  decoration: const InputDecoration(labelText: 'Group name (e.g. Add-ons, Toppings)'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.nonVegRed),
                onPressed: () => setState(() => _groups.removeAt(index)),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text('Allow multiple selections',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
              Switch(
                value: g.multi,
                onChanged: (v) => setState(() => g.multi = v),
              ),
              const SizedBox(width: 12),
              Text('Required (must choose)', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Switch(
                value: g.required,
                onChanged: (v) => setState(() => g.required = v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final it in g.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: it.name,
                      decoration: const InputDecoration(labelText: 'Option name'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: it.price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Price (₹)'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: AppColors.nonVegRed),
                    onPressed: () => setState(() => g.items.remove(it)),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () => setState(() => g.items.add(_DraftRow(name: '', price: null))),
            icon: const Icon(Icons.add),
            label: const Text('Add Option'),
          ),
        ],
      ),
    );
  }
}

/// One editable row (variant or modifier option): name + price controllers.
class _DraftRow {
  final TextEditingController name;
  final TextEditingController price;
  _DraftRow({required String name, required double? price})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price?.toStringAsFixed(2) ?? '');
}

/// One add-on group draft (name + switches + option rows).
class _GroupDraft {
  final TextEditingController name;
  bool multi;
  bool required;
  final List<_DraftRow> items;
  _GroupDraft({
    required String name,
    required this.multi,
    required this.required,
    required this.items,
  }) : name = TextEditingController(text: name);
}

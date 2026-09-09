import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/menu_model.dart';
import '../../widgets/custom_badge.dart';

class VariantAndModifiersDialog extends StatefulWidget {
  final MenuItem item;
  final Function(ProductVariant? variant, List<ModifierItem> modifiers, String? note, int quantity) onConfirm;

  const VariantAndModifiersDialog({
    super.key,
    required this.item,
    required this.onConfirm,
  });

  static void show(
    BuildContext context, {
    required MenuItem item,
    required Function(ProductVariant? variant, List<ModifierItem> modifiers, String? note, int quantity) onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => VariantAndModifiersDialog(item: item, onConfirm: onConfirm),
    );
  }

  @override
  State<VariantAndModifiersDialog> createState() => _VariantAndModifiersDialogState();
}

class _VariantAndModifiersDialogState extends State<VariantAndModifiersDialog> {
  ProductVariant? _selectedVariant;
  late List<ModifierGroup> _modifierGroups;
  int _quantity = 1;
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.item.hasVariants) {
      _selectedVariant = widget.item.variants.first;
    }
    // Deep clone modifier groups
    _modifierGroups = widget.item.modifierGroups.map((g) => g.copy()).toList();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  double get _computedUnitPrice {
    double base = _selectedVariant != null ? _selectedVariant!.price : widget.item.price;
    double modTotal = 0;
    for (var group in _modifierGroups) {
      for (var mod in group.items) {
        if (mod.isSelected) modTotal += mod.price;
      }
    }
    return base + modTotal;
  }

  double get _totalPrice => _computedUnitPrice * _quantity;

  List<ModifierItem> get _selectedModifiers {
    final list = <ModifierItem>[];
    for (var g in _modifierGroups) {
      for (var m in g.items) {
        if (m.isSelected) list.add(m);
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: SizedBox(
          width: 580,
          child: Column(
          children: [
            // Header with Dish info
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  VegMark(isVeg: widget.item.isVeg, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        Text(
                          widget.item.category,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),
            // Options Scrollable Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Variants (e.g. Size: Regular, Medium, Large)
                    if (widget.item.hasVariants) ...[
                      const Text(
                        'Choose Size / Portion',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: widget.item.variants.map((v) {
                          final isSelected = _selectedVariant?.id == v.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primaryOrangeLight : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? AppColors.primaryOrange : AppColors.borderLight,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: InkWell(
                              onTap: () => setState(() => _selectedVariant = v),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: isSelected ? AppColors.primaryOrange : AppColors.textLight,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        v.name,
                                        style: TextStyle(
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '₹${v.price.toStringAsFixed(0)}',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Modifier Groups (Toppings, Cooking Preferences)
                    for (var group in _modifierGroups) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              group.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            group.isMultiSelect ? 'Choose any' : 'Choose 1',
                            style: const TextStyle(color: AppColors.textLight, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: group.items.map((mod) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: mod.isSelected ? AppColors.primaryOrangeLight : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: mod.isSelected ? AppColors.primaryOrange : AppColors.borderLight,
                                width: mod.isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: CheckboxListTile(
                              value: mod.isSelected,
                              activeColor: AppColors.primaryOrange,
                              title: Text(
                                mod.name,
                                style: TextStyle(
                                  fontWeight: mod.isSelected ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                              secondary: mod.price > 0
                                  ? Text(
                                      '+₹${mod.price.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: AppColors.primaryOrange,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                              onChanged: (checked) {
                                setState(() {
                                  if (!group.isMultiSelect) {
                                    // Allow deselecting the chosen option
                                    // (required groups block confirm below).
                                    final wasSelected = mod.isSelected;
                                    for (var other in group.items) {
                                      other.isSelected = false;
                                    }
                                    mod.isSelected = !wasSelected;
                                  } else {
                                    mod.isSelected = checked ?? false;
                                  }
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Cooking / Special Instructions
                    const Text(
                      'Cooking Instructions',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Less spicy, no garlic, crisp base...',
                        prefixIcon: Icon(Icons.mode_edit_outline, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),
            // Bottom Action Bar: Quantity & Add Button
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.borderMedium),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          icon: const Icon(Icons.remove, size: 18),
                          onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '$_quantity',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => setState(() => _quantity++),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () {
                          // Enforce required modifier groups.
                          final missing = _modifierGroups
                              .where((g) => g.isRequired && !g.items.any((m) => m.isSelected))
                              .map((g) => g.name)
                              .toList();
                          if (missing.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Please choose: ${missing.join(", ")}'),
                                backgroundColor: AppColors.nonVegRed,
                              ),
                            );
                            return;
                          }
                          widget.onConfirm(
                            _selectedVariant,
                            _selectedModifiers,
                            _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
                            _quantity,
                          );
                          Navigator.of(context).pop();
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Text(
                                'Add to Order',
                                style: TextStyle(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '₹${_totalPrice.toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

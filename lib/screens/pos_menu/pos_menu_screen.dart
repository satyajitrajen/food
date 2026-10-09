import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../models/order_model.dart';
import '../../core/media.dart';
import '../../providers/pos_provider.dart';
import '../../models/menu_model.dart';
import '../../widgets/custom_badge.dart';
import '../modals/variant_and_modifiers_dialog.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/system_insets.dart';
import '../cart/cart_view.dart';
import '../order_flow/table_selection_screen.dart';

class PosMenuScreen extends StatefulWidget {
  const PosMenuScreen({super.key});

  @override
  State<PosMenuScreen> createState() => _PosMenuScreenState();
}

class _PosMenuScreenState extends State<PosMenuScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _adding = false;

  /// Plain dishes add in one tap; dishes with variants/add-ons (or a long
  /// press on any dish, for a note) open the customisation dialog.
  void _handleItemTap(BuildContext context, MenuItem item, PosProvider provider,
      {bool customise = false}) {
    if (_adding) return;
    if (!customise && !item.hasVariants && !item.hasModifiers) {
      provider.addToCart(item);
      return;
    }
    _adding = true;
    VariantAndModifiersDialog.show(
      context,
      item: item,
      onConfirm: (variant, modifiers, note, qty) {
        provider.addToCart(
          item,
          variant: variant,
          modifiers: modifiers,
          note: note,
          quantity: qty,
        );
      },
    ).whenComplete(() => _adding = false);
  }

  Future<void> _pickOrderType(BuildContext context, PosProvider provider, OrderType type) async {
    if (type != OrderType.delivery) {
      provider.setNewOrderType(type);
      return;
    }
    final address = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delivery details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Customer mobile'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: address,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Delivery address'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Start delivery order')),
        ],
      ),
    );
    if (ok == true) {
      provider.setNewOrderType(
        OrderType.delivery,
        customerPhone: phone.text.trim().isEmpty ? null : phone.text.trim(),
        address: address.text.trim().isEmpty ? null : address.text.trim(),
      );
    }
    address.dispose();
    phone.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tablets/desktop: menu and the running cart side by side, so adding,
        // sending the KOT and billing never leave this screen.
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              Expanded(child: _buildMenu(context, wide: true)),
              const VerticalDivider(width: 1, color: AppColors.borderLight),
              const SizedBox(width: 400, child: CartViewScreen(embedded: true)),
            ],
          );
        }
        return _buildMenu(context, wide: false);
      },
    );
  }

  Widget _buildMenu(BuildContext context, {required bool wide}) {
    final provider = context.watch<PosProvider>();
    final activeOrder = provider.activeOrder;
    final tableNumber = activeOrder?.tableNumber ?? provider.selectedTable?.tableNumber;
    final orderLabel = tableNumber != null
        ? 'Table $tableNumber'
        : (activeOrder?.orderTypeLabel ?? provider.newOrderType.label);
    final cartCount = activeOrder?.totalItemCount ?? 0;

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        title: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TableSelectionScreen(isSelectingForOrder: true)),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    orderLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              provider.filterVegOnly ? Icons.eco : Icons.eco_outlined,
              color: provider.filterVegOnly ? AppColors.vegGreen : AppColors.textMuted,
            ),
            tooltip: 'Filter Pure Veg',
            onPressed: () => provider.toggleVegOnly(),
          ),
          IconButton(
            tooltip: 'View order',
            icon: Badge(
              isLabelVisible: cartCount > 0,
              label: Text('$cartCount'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CartViewScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (tableNumber == null)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<OrderType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: OrderType.takeaway, icon: Icon(Icons.shopping_bag_outlined), label: Text('Takeaway')),
                  ButtonSegment(value: OrderType.delivery, icon: Icon(Icons.delivery_dining_outlined), label: Text('Delivery')),
                  ButtonSegment(value: OrderType.dineIn, icon: Icon(Icons.table_restaurant_outlined), label: Text('Table')),
                ],
                selected: {activeOrder?.orderType ?? provider.newOrderType},
                onSelectionChanged: (sel) {
                  final type = sel.first;
                  if (type == OrderType.dineIn) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TableSelectionScreen(isSelectingForOrder: true)),
                    );
                  } else {
                    _pickOrderType(context, provider, type);
                  }
                },
              ),
            ),
          // Search Box
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => provider.setSearchQuery(val),
              decoration: InputDecoration(
                hintText: 'Search dishes by name or category...',
                prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textLight),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          provider.setSearchQuery('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                fillColor: AppColors.creamSubtle,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Category Pills Scroll
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: provider.categories.map((cat) {
                  final isSelected = provider.selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      selectedColor: AppColors.primaryGreen,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      onSelected: (_) => provider.setCategory(cat),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),

          // Dishes Grid
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 2;
                if (constraints.maxWidth > 1000) {
                  crossAxisCount = 4;
                } else if (constraints.maxWidth > 700) {
                  crossAxisCount = 3;
                }

                final items = provider.filteredMenuItems;

                if (items.isEmpty) {
                  return const Center(
                    child: Text('No dishes match your search or filters.', style: TextStyle(color: AppColors.textMuted)),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildDishCard(context, item, provider);
                  },
                );
              },
            ),
          ),
        ],
      ),
      // Bottom Floating Cart Bar (explicit bottom inset: bare SafeArea inside
      // bottomSheet slides under the opaque system nav on some devices).
      bottomSheet: (!wide && activeOrder != null && activeOrder.items.isNotEmpty)
          ? Container(
              padding: BottomInsets.barAll(context),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${plural(activeOrder.totalItemCount, 'item')} · ${formatInr(activeOrder.subtotal)} + tax',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textDark),
                        ),
                        Text(
                          orderLabel,
                          style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CartViewScreen()),
                        );
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('View Order', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildDishCard(BuildContext context, MenuItem item, PosProvider provider) {
    // Count how many of this item are currently in cart
    final cartQty = provider.activeOrder?.items
            .where((i) => !i.isCancelled && i.menuItem.id == item.id)
            .fold(0, (sum, i) => sum + i.quantity) ??
        0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _handleItemTap(context, item, provider),
        onLongPress: () => _handleItemTap(context, item, provider, customise: true),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cartQty > 0 ? AppColors.primaryGreen.withValues(alpha: 0.5) : AppColors.borderLight,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Image with Veg/Non-Veg Tag
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  child: Builder(
                    builder: (context) {
                      final imageUrl = resolveMediaUrl(item.imageUrl, apiBase: context.read<PosProvider>().apiBaseUrl);
                      if (imageUrl.isEmpty) {
                        return Container(
                          color: AppColors.creamSubtle,
                          child: const Center(
                            child: Icon(Icons.fastfood, color: AppColors.textLight, size: 36),
                          ),
                        );
                      }
                      return Image.network(
                        imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.creamSubtle,
                          child: const Center(
                            child: Icon(Icons.fastfood, color: AppColors.textLight, size: 36),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                      ],
                    ),
                    child: VegMark(isVeg: item.isVeg, size: 12),
                  ),
                ),
                if (item.isBestseller)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.saffronAmber,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'BESTSELLER',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      if (item.hasVariants || item.hasModifiers)
                        const Text(
                          'Customizable',
                          style: TextStyle(color: AppColors.primaryGreen, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatInr(item.price),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textDark),
                      ),
                      if (cartQty == 0)
                        InkWell(
                          onTap: () => _handleItemTap(context, item, provider),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreenLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'ADD',
                              style: TextStyle(
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () async {
                                  final matching = provider.activeOrder?.items
                                          .where((i) => !i.isCancelled && i.menuItem.id == item.id)
                                          .toList() ??
                                      [];
                                  if (matching.isEmpty) return;
                                  // Per-variant safety: with multiple distinct lines
                                  // (e.g. Half vs Full), don't guess — let the user
                                  // pick the exact line in the cart.
                                  if (matching.length > 1) {
                                    if (!context.mounted) return;
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => const CartViewScreen()),
                                    );
                                    return;
                                  }
                                  final orderItem = matching.first;
                                  if (orderItem.quantity <= 1) {
                                    final ok = await showConfirmDialog(
                                      context,
                                      title: 'Remove item?',
                                      message:
                                          'Remove "${orderItem.displayName}" from the cart?',
                                      confirmLabel: 'Remove Item',
                                    );
                                    if (!ok || !context.mounted) return;
                                  }
                                  provider.decrementItem(orderItem);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(Icons.remove, size: 16, color: Colors.white),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  '$cartQty',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                                ),
                              ),
                              InkWell(
                                onTap: () => _handleItemTap(context, item, provider),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(Icons.add, size: 16, color: Colors.white),
                                ),
                              ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

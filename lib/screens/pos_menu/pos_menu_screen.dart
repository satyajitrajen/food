import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/media.dart';
import '../../providers/pos_provider.dart';
import '../../models/menu_model.dart';
import '../../widgets/custom_badge.dart';
import '../modals/variant_and_modifiers_dialog.dart';
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

  void _handleItemTap(BuildContext context, MenuItem item, PosProvider provider) {
    if (item.hasVariants || item.hasModifiers) {
      // Open Customization Modal
      VariantAndModifiersDialog.show(
        context,
        item: item,
        onConfirm: (variant, modifiers, note, qty) {
          for (int i = 0; i < qty; i++) {
            provider.addToCart(
              item,
              variant: variant,
              modifiers: modifiers,
              note: note,
            );
          }
        },
      );
    } else {
      // Simple direct add to cart
      provider.addToCart(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final activeOrder = provider.activeOrder;
    final tableName = activeOrder?.tableNumber ?? provider.selectedTable?.tableNumber ?? 'Counter';

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              provider.goToHome(); // return to role home
            }
          },
        ),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Table $tableName',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textDark),
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
            icon: const Icon(Icons.shopping_bag_outlined),
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
                      selectedColor: AppColors.primaryOrange,
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
      // Bottom Floating Cart Bar
      bottomSheet: (activeOrder != null && activeOrder.items.isNotEmpty)
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${activeOrder.totalItemCount} Items · ₹${activeOrder.subtotal.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textDark),
                        ),
                        Text(
                          'Table $tableName',
                          style: const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryOrange,
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cartQty > 0 ? AppColors.primaryOrange.withValues(alpha: 0.5) : AppColors.borderLight,
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
                          style: TextStyle(color: AppColors.primaryOrange, fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '₹${item.price.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.textDark),
                      ),
                      if (cartQty == 0)
                        InkWell(
                          onTap: () => _handleItemTap(context, item, provider),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryOrangeLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'ADD',
                              style: TextStyle(
                                color: AppColors.primaryOrange,
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
                            color: AppColors.primaryOrange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  final orderItem = provider.activeOrder?.items
                                      .where((i) => !i.isCancelled && i.menuItem.id == item.id)
                                      .firstOrNull;
                                  if (orderItem != null) provider.decrementItem(orderItem);
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
    );
  }
}

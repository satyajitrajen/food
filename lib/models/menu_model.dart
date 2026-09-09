class ProductVariant {
  final String id;
  final String name; // e.g. 'Regular', 'Medium', 'Large'
  final double price;

  ProductVariant({
    required this.id,
    required this.name,
    required this.price,
  });

  ProductVariant copy() => ProductVariant(id: id, name: name, price: price);
}

class ModifierItem {
  final String id;
  final String name;
  final double price;
  bool isSelected;

  ModifierItem({
    required this.id,
    required this.name,
    required this.price,
    this.isSelected = false,
  });

  ModifierItem copy() => ModifierItem(
        id: id,
        name: name,
        price: price,
        isSelected: isSelected,
      );
}

class ModifierGroup {
  final String id;
  final String name; // e.g. 'Pizza Toppings', 'Cooking Preference'
  final bool isMultiSelect;
  final bool isRequired;
  final List<ModifierItem> items;

  ModifierGroup({
    required this.id,
    required this.name,
    required this.isMultiSelect,
    this.isRequired = false,
    required this.items,
  });

  ModifierGroup copy() => ModifierGroup(
        id: id,
        name: name,
        isMultiSelect: isMultiSelect,
        isRequired: isRequired,
        items: items.map((i) => i.copy()).toList(),
      );
}

class MenuItem {
  final String id;
  final String name;
  final String category;
  final double price;
  final bool isVeg;
  final String imageUrl;
  final String description;
  final List<ProductVariant> variants;
  final List<ModifierGroup> modifierGroups;
  final bool isBestseller;
  final bool isAvailable;

  MenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.isVeg,
    required this.imageUrl,
    this.description = '',
    this.variants = const [],
    this.modifierGroups = const [],
    this.isBestseller = false,
    this.isAvailable = true,
  });

  bool get hasVariants => variants.isNotEmpty;
  bool get hasModifiers => modifierGroups.isNotEmpty;

  MenuItem copy() => MenuItem(
        id: id,
        name: name,
        category: category,
        price: price,
        isVeg: isVeg,
        imageUrl: imageUrl,
        description: description,
        variants: variants.map((v) => v.copy()).toList(),
        modifierGroups: modifierGroups.map((g) => g.copy()).toList(),
        isBestseller: isBestseller,
        isAvailable: isAvailable,
      );

  MenuItem copyWith({
    String? name,
    String? category,
    double? price,
    bool? isVeg,
    String? imageUrl,
    String? description,
    List<ProductVariant>? variants,
    List<ModifierGroup>? modifierGroups,
    bool? isBestseller,
    bool? isAvailable,
  }) =>
      MenuItem(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        price: price ?? this.price,
        isVeg: isVeg ?? this.isVeg,
        imageUrl: imageUrl ?? this.imageUrl,
        description: description ?? this.description,
        variants: variants ?? this.variants.map((v) => v.copy()).toList(),
        modifierGroups:
            modifierGroups ?? this.modifierGroups.map((g) => g.copy()).toList(),
        isBestseller: isBestseller ?? this.isBestseller,
        isAvailable: isAvailable ?? this.isAvailable,
      );
}

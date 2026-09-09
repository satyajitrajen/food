enum ExpenseCategory {
  rent,
  electricity,
  gas,
  salary,
  maintenance,
  transport,
  miscellaneous,
  rawMaterials,
}

class Expense {
  final String id;
  final String title;
  final ExpenseCategory category;
  final double amount;
  final DateTime date;
  final String paymentMethod; // 'Cash', 'UPI', 'Card', 'Bank Transfer'
  final String? vendor;
  final String? reference;
  final String? description;

  Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    required this.paymentMethod,
    this.vendor,
    this.reference,
    this.description,
  });

  String get categoryLabel {
    switch (category) {
      case ExpenseCategory.rent:
        return 'Rent';
      case ExpenseCategory.electricity:
        return 'Electricity';
      case ExpenseCategory.gas:
        return 'Gas';
      case ExpenseCategory.salary:
        return 'Salary';
      case ExpenseCategory.maintenance:
        return 'Maintenance';
      case ExpenseCategory.transport:
        return 'Transport';
      case ExpenseCategory.miscellaneous:
        return 'Miscellaneous';
      case ExpenseCategory.rawMaterials:
        return 'Raw Materials';
    }
  }
}

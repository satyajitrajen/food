enum StaffRole { admin, manager, cashier, waiter, kitchen }

class Staff {
  final String id;
  final String name;
  final StaffRole role;
  final String pin;
  final String avatarUrl;
  final String mobile;
  final bool isActive;

  Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.pin,
    required this.avatarUrl,
    required this.mobile,
    this.isActive = true,
  });

  String get roleTitle {
    switch (role) {
      case StaffRole.admin:
        return 'Admin';
      case StaffRole.manager:
        return 'Manager';
      case StaffRole.cashier:
        return 'Cashier';
      case StaffRole.waiter:
        return 'Waiter';
      case StaffRole.kitchen:
        return 'Kitchen';
    }
  }
}

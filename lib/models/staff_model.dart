enum StaffRole { admin, manager, cashier, waiter, kitchen }

class Staff {
  final String id;
  final String? outletId;
  final String name;
  final StaffRole role;
  final String pin;
  final String avatarUrl;
  final String mobile;
  final bool isActive;
  final bool isProtected;

  Staff({
    required this.id,
    this.outletId,
    required this.name,
    required this.role,
    required this.pin,
    required this.avatarUrl,
    required this.mobile,
    this.isActive = true,
    this.isProtected = false,
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

  /// Whether this staff member is allowed to operate in [targetOutletId].
  /// Waiters and kitchen staff are strictly single-outlet; other roles may be
  /// org-wide floaters when [outletId] is null.
  bool canAccessOutlet(String? targetOutletId) {
    if (outletId == null) {
      return role != StaffRole.waiter && role != StaffRole.kitchen;
    }
    return outletId == targetOutletId;
  }
}

/// Attendance ledger entry: a clock-in / clock-out pair (terminal-local).
class AttendanceEntry {
  final String id;
  final String staffId;
  final String staffName;
  final DateTime clockIn;
  DateTime? clockOut;

  AttendanceEntry({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.clockIn,
    this.clockOut,
  });

  /// Minutes worked for this session; open sessions count up to now.
  int get minutesWorked {
    final end = clockOut ?? DateTime.now();
    final diff = end.difference(clockIn).inMinutes;
    return diff.isNegative ? 0 : diff;
  }

  bool get isOnDuty => clockOut == null;
}

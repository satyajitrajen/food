/// Top-level app destinations rendered by [MainAdaptiveShell].
///
/// Each role gets its own ordered list of these destinations
/// (`PosProvider.navDestinations`); the shell maps every destination to a
/// screen, icon and label. "more" is the mobile hub that holds role-filtered
/// secondary screens.
enum AppDest {
  dashboard,
  runningOrders,
  pos,
  tables,
  kitchen,
  transactions,
  shiftCash,
  expenses,
  customers,
  inventory,
  reports,
  settings,
  more,
}

extension AppDestLabel on AppDest {
  String get label {
    switch (this) {
      case AppDest.dashboard:
        return 'Home';
      case AppDest.runningOrders:
        return 'Orders';
      case AppDest.pos:
        return 'POS';
      case AppDest.tables:
        return 'Tables';
      case AppDest.kitchen:
        return 'Kitchen';
      case AppDest.transactions:
        return 'Transactions';
      case AppDest.shiftCash:
        return 'Shift & Cash';
      case AppDest.expenses:
        return 'Expenses';
      case AppDest.customers:
        return 'Customers';
      case AppDest.inventory:
        return 'Inventory';
      case AppDest.reports:
        return 'Reports';
      case AppDest.settings:
        return 'Settings';
      case AppDest.more:
        return 'More';
    }
  }
}

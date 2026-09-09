import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_nav.dart';
import '../../models/staff_model.dart';
import '../../providers/pos_provider.dart';
import '../../models/outlet_model.dart';
import '../dashboard/pos_dashboard_screen.dart';
import '../running_orders/running_orders_screen.dart';
import '../pos_menu/pos_menu_screen.dart';
import '../order_flow/table_selection_screen.dart';
import '../more/more_hub_screen.dart';
import '../kitchen/kitchen_board_screen.dart';
import '../transactions/transactions_screen.dart';
import '../customers/customer_screen.dart';
import '../inventory/inventory_screen.dart';
import '../expenses/expense_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../shift/shift_dashboard_screen.dart';
import '../auth/pin_login_screen.dart';

/// Role-aware shell. Each role gets its own ordered destination list
/// (PosProvider.navDestinations); the index drives both the mobile bottom bar
/// and the desktop sidebar, so cross-screen jumps always land on the right tab.
class MainAdaptiveShell extends StatefulWidget {
  const MainAdaptiveShell({super.key});

  @override
  State<MainAdaptiveShell> createState() => _MainAdaptiveShellState();
}

class _MainAdaptiveShellState extends State<MainAdaptiveShell> {
  // Primary tabs shown on the mobile bottom bar (subset of navDestinations).
  List<AppDest> _mobileTabs(StaffRole? role) {
    switch (role) {
      case StaffRole.admin:
        return const [
          AppDest.dashboard,
          AppDest.runningOrders,
          AppDest.pos,
          AppDest.tables,
          AppDest.more,
        ];
      case StaffRole.manager:
      case StaffRole.cashier:
        return const [
          AppDest.pos,
          AppDest.runningOrders,
          AppDest.tables,
          AppDest.more,
        ];
      case StaffRole.waiter:
        return const [
          AppDest.tables,
          AppDest.runningOrders,
          AppDest.pos,
          AppDest.more,
        ];
      default:
        return const [AppDest.more];
    }
  }

  Widget _screenFor(AppDest dest) {
    switch (dest) {
      case AppDest.dashboard:
        return const PosDashboardScreen();
      case AppDest.runningOrders:
        return const RunningOrdersScreen();
      case AppDest.pos:
        return const PosMenuScreen();
      case AppDest.tables:
        return const TableSelectionScreen();
      case AppDest.kitchen:
        return const KitchenBoardScreen();
      case AppDest.transactions:
        return const TransactionsScreen();
      case AppDest.shiftCash:
        return const ShiftDashboardScreen();
      case AppDest.expenses:
        return const ExpenseScreen();
      case AppDest.customers:
        return const CustomerScreen();
      case AppDest.inventory:
        return const InventoryScreen();
      case AppDest.reports:
        return const ReportsScreen();
      case AppDest.settings:
        return const SettingsScreen();
      case AppDest.more:
        return const MoreHubScreen();
    }
  }

  IconData _iconFor(AppDest dest) {
    switch (dest) {
      case AppDest.dashboard:
        return Icons.dashboard_outlined;
      case AppDest.runningOrders:
        return Icons.receipt_long_outlined;
      case AppDest.pos:
        return Icons.add_circle;
      case AppDest.tables:
        return Icons.table_restaurant_outlined;
      case AppDest.kitchen:
        return Icons.soup_kitchen_outlined;
      case AppDest.transactions:
        return Icons.receipt_outlined;
      case AppDest.shiftCash:
        return Icons.alarm_on_outlined;
      case AppDest.expenses:
        return Icons.money_off_outlined;
      case AppDest.customers:
        return Icons.people_outline;
      case AppDest.inventory:
        return Icons.inventory_2_outlined;
      case AppDest.reports:
        return Icons.analytics_outlined;
      case AppDest.settings:
        return Icons.settings_outlined;
      case AppDest.more:
        return Icons.grid_view_outlined;
    }
  }

  IconData _selectedIconFor(AppDest dest) {
    switch (dest) {
      case AppDest.dashboard:
        return Icons.dashboard;
      case AppDest.pos:
        return Icons.add_circle;
      case AppDest.tables:
        return Icons.table_restaurant;
      default:
        return _iconFor(dest);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Select only what this shell renders — avoid full-app rebuilds.
    final navIndex = context.select<PosProvider, int>((p) => p.currentNavIndex);
    final role = context.select<PosProvider, StaffRole?>((p) => p.currentStaff?.role);
    final staffName = context.select<PosProvider, String?>((p) => p.currentStaff?.name);
    final outlet = context.select<PosProvider, Outlet>((p) => p.currentOutlet);
    final provider = context.read<PosProvider>();

    final destinations = provider.navDestinations;
    if (destinations.isEmpty) {
      // Kitchen has no shell destinations; render the locked KDS directly.
      return const KitchenBoardScreen(showLock: true);
    }
    final index = navIndex.clamp(0, destinations.length - 1);
    final currentDest = destinations[index];
    final tabs = _mobileTabs(role);
    final screens = destinations.map(_screenFor).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = constraints.maxWidth >= 850;

        if (!isLargeScreen) {
          // Mobile / Handheld Navigation Shell
          final selectedTab =
              tabs.contains(currentDest) ? tabs.indexOf(currentDest) : tabs.length - 1;
          return Scaffold(
            body: IndexedStack(
              index: index,
              children: screens,
            ),
            bottomNavigationBar: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.borderLight, width: 1.2)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: NavigationBar(
                  selectedIndex: selectedTab,
                  onDestinationSelected: (tabPosition) {
                    provider.goToDest(tabs[tabPosition]);
                  },
                  backgroundColor: Colors.white,
                  indicatorColor: AppColors.primaryOrangeLight,
                  destinations: [
                    for (final d in tabs)
                      NavigationDestination(
                        icon: Icon(_iconFor(d)),
                        selectedIcon: Icon(
                          _selectedIconFor(d),
                          color: d == AppDest.pos ? AppColors.primaryOrangeDark : AppColors.primaryOrange,
                        ),
                        label: d.label,
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        // Tablet & Desktop Sidebar Navigation Shell
        final sidebarDests =
            destinations.where((d) => d != AppDest.more).toList();
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                // Persistent Left Sidebar
                Container(
                  width: 240,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: AppColors.borderLight, width: 1.2)),
                  ),
                  child: Column(
                    children: [
                      // Brand Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primaryOrange,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.restaurant, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('RESTO POS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
                                Text(outlet.terminal, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.borderLight),
                      // Navigation List
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          children: [
                            for (final d in sidebarDests)
                              _buildSidebarItem(
                                provider,
                                destinations.indexOf(d),
                                index,
                                d,
                              ),
                          ],
                        ),
                      ),
                      // Current Staff Profile & Lock
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: AppColors.borderLight)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.primaryOrangeLight,
                              child: Text(
                                _initialOf(staffName),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryOrange, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    staffName ?? 'Staff',
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                  Text(
                                    provider.currentStaff?.roleTitle ?? '',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
                              tooltip: 'Lock Register',
                              onPressed: () {
                                provider.logout();
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const PinLoginScreen()),
                                  (route) => false,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Content Area
                Expanded(
                  child: IndexedStack(
                    index: index,
                    children: screens,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebarItem(PosProvider provider, int destIndex, int currentIndex, AppDest dest) {
    final isSelected = currentIndex == destIndex;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryOrangeLight : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(
          _iconFor(dest),
          color: isSelected ? AppColors.primaryOrange : AppColors.textDark,
          size: 20,
        ),
        title: Text(
          dest.label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
            color: isSelected ? AppColors.primaryOrange : AppColors.textDark,
          ),
        ),
        onTap: () => provider.goToDest(dest),
      ),
    );
  }

  static String _initialOf(String? name) {
    final n = name ?? '';
    return n.isEmpty ? 'S' : n[0];
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../more/my_profile_screen.dart';

/// Role-aware shell. Each role gets its own ordered destination list
/// (PosProvider.navDestinations); the index drives both the mobile bottom bar
/// and the desktop sidebar, so cross-screen jumps always land on the right tab.
class MainAdaptiveShell extends StatefulWidget {
  const MainAdaptiveShell({super.key});

  @override
  State<MainAdaptiveShell> createState() => _MainAdaptiveShellState();
}

class _MainAdaptiveShellState extends State<MainAdaptiveShell> {
  static const _sidebarCollapsedKey = 'shell.sidebar_collapsed';
  static const _sidebarWide = 240.0;
  static const _sidebarNarrow = 72.0;

  /// Large-screen sidebar shrunk to an icon strip; remembered per device.
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _loadSidebarPref();
  }

  Future<void> _loadSidebarPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final collapsed = prefs.getBool(_sidebarCollapsedKey) ?? false;
      if (mounted && collapsed != _sidebarCollapsed) {
        setState(() => _sidebarCollapsed = collapsed);
      }
    } catch (_) {
      // Preference is a convenience; default to expanded.
    }
  }

  void _toggleSidebar() {
    setState(() => _sidebarCollapsed = !_sidebarCollapsed);
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_sidebarCollapsedKey, _sidebarCollapsed))
        .catchError((_) => false);
  }

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
    final role = context.select<PosProvider, StaffRole?>(
      (p) => p.currentStaff?.role,
    );
    final staffName = context.select<PosProvider, String?>(
      (p) => p.currentStaff?.name,
    );
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
        final width = constraints.maxWidth;

        if (width < 600) {
          // Mobile / Handheld Navigation Shell
          final selectedTab = tabs.contains(currentDest)
              ? tabs.indexOf(currentDest)
              : tabs.length - 1;
          return Scaffold(
            body: IndexedStack(index: index, children: screens),
            bottomNavigationBar: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: AppColors.borderLight, width: 1.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
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
                  indicatorColor: AppColors.primaryGreenLight,
                  destinations: [
                    for (final d in tabs)
                      NavigationDestination(
                        icon: Icon(_iconFor(d)),
                        selectedIcon: Icon(
                          _selectedIconFor(d),
                          color: d == AppDest.pos
                              ? AppColors.primaryGreenDark
                              : AppColors.primaryGreen,
                        ),
                        label: d.label,
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        if (width < 1024) {
          // Tablet: compact rail with every destination (incl. More, which
          // holds Menu/Staff/Printer/Cash drawer/Attendance/QR/Switch outlet).
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: c.maxHeight),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            selectedIndex: index,
                            onDestinationSelected: (i) =>
                                provider.goToDest(destinations[i]),
                            labelType: NavigationRailLabelType.all,
                            backgroundColor: AppColors.creamCard,
                            indicatorColor: AppColors.primaryGreenLight,
                            trailing: IconButton(
                              tooltip: 'Lock register',
                              icon: const Icon(Icons.lock_outline),
                              onPressed: () {
                                provider.logout();
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) => const PinLoginScreen(),
                                  ),
                                  (route) => false,
                                );
                              },
                            ),
                            destinations: [
                              for (final d in destinations)
                                NavigationRailDestination(
                                  icon: Icon(_iconFor(d)),
                                  selectedIcon: Icon(
                                    _selectedIconFor(d),
                                    color: AppColors.primaryGreen,
                                  ),
                                  label: Text(d.label),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppColors.borderLight),
                  Expanded(
                    child: IndexedStack(index: index, children: screens),
                  ),
                ],
              ),
            ),
          );
        }

        // Desktop / large tablet sidebar.
        final sidebarDests = destinations;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                // Persistent Left Sidebar (collapsible to an icon strip)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: _sidebarCollapsed ? _sidebarNarrow : _sidebarWide,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(
                        color: AppColors.borderLight,
                        width: 1.2,
                      ),
                    ),
                  ),
                  // Lay out by the live width so the animation never overflows.
                  child: LayoutBuilder(
                    builder: (context, c) => _buildSidebarContent(
                      context,
                      provider,
                      outlet,
                      staffName,
                      sidebarDests,
                      destinations,
                      index,
                      compact: c.maxWidth < 180,
                    ),
                  ),
                ),

                // Content Area
                Expanded(
                  child: IndexedStack(index: index, children: screens),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _lockRegister(BuildContext context, PosProvider provider) {
    provider.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PinLoginScreen()),
      (route) => false,
    );
  }

  Widget _buildSidebarContent(
    BuildContext context,
    PosProvider provider,
    Outlet outlet,
    String? staffName,
    List<AppDest> sidebarDests,
    List<AppDest> destinations,
    int index, {
    required bool compact,
  }) {
    final toggle = IconButton(
      tooltip: _sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
      icon: Icon(
        _sidebarCollapsed ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left,
        size: 20,
        color: AppColors.textMuted,
      ),
      onPressed: _toggleSidebar,
    );
    final avatar = InkWell(
      customBorder: const CircleBorder(),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const MyProfileScreen())),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.primaryGreenLight,
        child: Text(
          _initialOf(staffName),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.primaryGreen,
            fontSize: 13,
          ),
        ),
      ),
    );
    final lock = IconButton(
      icon: const Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
      tooltip: 'Lock Register',
      onPressed: () => _lockRegister(context, provider),
    );

    return Column(
      children: [
        // Brand header — full wordmark + outlet / terminal, or just the toggle.
        if (compact)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: toggle,
          )
        else
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 4, 12),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/logo.png',
                          height: 40,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          alignment: Alignment.centerLeft,
                          errorBuilder: (_, __, ___) => const Text(
                            'HISHOBKR',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [outlet.name, outlet.terminal].where((v) => v.isNotEmpty).join(' · '),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                toggle,
              ],
            ),
          ),
        const Divider(height: 1, color: AppColors.borderLight),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 12),
            children: [
              for (final d in sidebarDests)
                _buildSidebarItem(provider, destinations.indexOf(d), index, d, compact: compact),
            ],
          ),
        ),
        // Current staff profile & lock
        Container(
          padding: EdgeInsets.all(compact ? 8 : 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.borderLight)),
          ),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(message: staffName ?? 'Staff', child: avatar),
                    const SizedBox(height: 4),
                    lock,
                  ],
                )
              : Row(
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            staffName ?? 'Staff',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          Text(
                            provider.currentStaff?.roleTitle ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    lock,
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSidebarItem(
    PosProvider provider,
    int destIndex,
    int currentIndex,
    AppDest dest, {
    bool compact = false,
  }) {
    final isSelected = currentIndex == destIndex;
    if (compact) {
      return Tooltip(
        message: dest.label,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryGreenLight : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => provider.goToDest(dest),
            child: SizedBox(
              height: 44,
              child: Center(
                child: Icon(
                  _iconFor(dest),
                  color: isSelected ? AppColors.primaryGreen : AppColors.textDark,
                  size: 20,
                  semanticLabel: dest.label,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryGreenLight : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(
          _iconFor(dest),
          color: isSelected ? AppColors.primaryGreen : AppColors.textDark,
          size: 20,
        ),
        title: Text(
          dest.label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
            color: isSelected ? AppColors.primaryGreen : AppColors.textDark,
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

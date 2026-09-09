import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/staff_model.dart';
import '../../providers/pos_provider.dart';
import '../transactions/transactions_screen.dart';
import '../kitchen/kitchen_board_screen.dart';
import '../shift/shift_dashboard_screen.dart';
import '../cash_drawer/cash_drawer_screen.dart';
import '../expenses/expense_screen.dart';
import '../customers/customer_screen.dart';
import '../inventory/inventory_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/menu_admin_screen.dart';
import '../settings/staff_admin_screen.dart';
import '../auth/pin_login_screen.dart';
import '../auth/select_outlet_screen.dart';

/// Secondary operations hub. Tiles are filtered by role — Admin sees the
/// overall revenue area (Reports) that Manager/Cashier cannot, and back-office
/// tiles (menu/staff/settings) are management-only. Waiters keep a minimal hub
/// (profile + outlet switch + lock).
class MoreHubScreen extends StatelessWidget {
  const MoreHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final role = provider.currentStaff?.role;
    final isOps = role == StaffRole.admin || role == StaffRole.manager || role == StaffRole.cashier;
    final isAdmin = role == StaffRole.admin;
    final canManage = role == StaffRole.admin || role == StaffRole.manager;

    final tiles = <Widget>[
      if (isOps)
        _tile(
          context: context,
          title: 'Shift Dashboard & Cash',
          subtitle: 'Live float balance, Cash In/Out & Shift Closing',
          icon: Icons.alarm_on,
          color: AppColors.primaryOrange,
          bgColor: AppColors.primaryOrangeLight,
          screen: const ShiftDashboardScreen(),
        ),
      if (isOps)
        _tile(
          context: context,
          title: 'Kitchen Display (KDS)',
          subtitle: 'Live KOT order queues and ticket statuses',
          icon: Icons.soup_kitchen,
          color: AppColors.infoBlue,
          bgColor: AppColors.infoBlueBg,
          screen: const KitchenBoardScreen(),
        ),
      if (isOps)
        _tile(
          context: context,
          title: 'Past Transactions & Invoices',
          subtitle: 'View tax receipts, filter payments & issue refunds',
          icon: Icons.receipt_long,
          color: AppColors.vegGreen,
          bgColor: AppColors.vegGreenBg,
          screen: const TransactionsScreen(),
        ),
      if (isOps)
        _tile(
          context: context,
          title: 'Expense Management',
          subtitle: 'Log vendor payments, rent, utility bills & petty cash',
          icon: Icons.money_off,
          color: AppColors.nonVegRed,
          bgColor: AppColors.nonVegRedBg,
          screen: const ExpenseScreen(),
        ),
      if (isOps)
        _tile(
          context: context,
          title: 'Cash Drawer Math Ledger',
          subtitle: 'Live cash drawer tracking: Opening + Sales - Expenses',
          icon: Icons.point_of_sale,
          color: AppColors.saffronAmber,
          bgColor: AppColors.saffronAmberBg,
          screen: const CashDrawerScreen(),
        ),
      if (isOps)
        _tile(
          context: context,
          title: 'Customer Directory',
          subtitle: 'Customer contact book, visits, spend & credit ledger',
          icon: Icons.people_outline,
          color: AppColors.primaryOrange,
          bgColor: AppColors.primaryOrangeLight,
          screen: const CustomerScreen(),
        ),
      if (isOps)
        _tile(
          context: context,
          title: 'Inventory & Suppliers',
          subtitle: 'Stock balances, low stock alerts & purchase history',
          icon: Icons.inventory_2_outlined,
          color: AppColors.infoBlue,
          bgColor: AppColors.infoBlueBg,
          screen: const InventoryScreen(),
        ),
      // Overall revenue analytics — Admin only.
      if (isAdmin)
        _tile(
          context: context,
          title: 'Reports & Analytics',
          subtitle: 'Daily gross/net sales, category breakdown & profit snapshot',
          icon: Icons.analytics_outlined,
          color: AppColors.vegGreen,
          bgColor: AppColors.vegGreenBg,
          screen: const ReportsScreen(),
        ),
      // Back-office management (Admin/Manager; server enforces too).
      if (canManage)
        _tile(
          context: context,
          title: 'Menu Management',
          subtitle: 'Add/edit items, categories, prices & availability',
          icon: Icons.restaurant_menu,
          color: AppColors.primaryOrange,
          bgColor: AppColors.primaryOrangeLight,
          screen: const MenuAdminScreen(),
        ),
      if (canManage)
        _tile(
          context: context,
          title: 'Staff Management',
          subtitle: 'Add staff, roles, PIN resets & account status',
          icon: Icons.badge_outlined,
          color: AppColors.infoBlue,
          bgColor: AppColors.infoBlueBg,
          screen: const StaffAdminScreen(),
        ),
      if (canManage)
        _tile(
          context: context,
          title: 'POS Configuration & Settings',
          subtitle: 'Hotel profile, dining sections, tables, tax & printers',
          icon: Icons.settings_outlined,
          color: AppColors.textDark,
          bgColor: AppColors.creamSubtle,
          screen: const SettingsScreen(),
        ),
      _tile(
        context: context,
        title: 'Switch Outlet / Terminal',
        subtitle: 'Currently connected to ${provider.currentOutlet.name}',
        icon: Icons.store_mall_directory_outlined,
        color: AppColors.textDark,
        bgColor: AppColors.creamSubtle,
        screen: const SelectOutletScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.creamBg,
      appBar: AppBar(
        title: const Text('Restaurant Operations', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Staff Profile Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.primaryOrangeLight,
                    backgroundImage: NetworkImage(provider.currentStaff?.avatarUrl ?? ''),
                    onBackgroundImageError: (_, _) {},
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.currentStaff?.name ?? 'Staff',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        Text(
                          '${provider.currentStaff?.roleTitle ?? ""} · ${provider.currentOutlet.name} (${provider.currentOutlet.terminal})',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: AppColors.nonVegRed),
                    tooltip: 'Lock Register / Switch Staff',
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
            const SizedBox(height: 20),
            ...tiles,
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Widget screen,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textLight),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

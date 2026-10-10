// Isolated in-memory demo. Restart the app to reset the scenario data.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:food_pos/core/theme/app_theme.dart';
import 'package:food_pos/models/menu_model.dart';
import 'package:food_pos/models/outlet_model.dart';
import 'package:food_pos/models/staff_model.dart';
import 'package:food_pos/models/table_model.dart';
import 'package:food_pos/providers/pos_provider.dart';
import 'package:food_pos/screens/auth/pin_login_screen.dart';

PosProvider createDemoProvider() {
  final pos = PosProvider();
  // The fixture loader is intentional in this separate demo entry point.
  // ignore: invalid_use_of_visible_for_testing_member
  pos.loadFixture(
    outlets: [Outlet(id: 'demo', name: 'Spice Haven Demo', terminal: 'POS-01')],
    staff: StaffRole.values.map((role) => Staff(
      id: role.name, outletId: 'demo', name: 'Demo ${role.name}',
      role: role, pin: '1234', avatarUrl: '', mobile: '',
    )).toList(),
    tables: [
      RestaurantTable(id: 't1', tableNumber: 'T1', seats: 4, floor: 'Dining'),
      RestaurantTable(id: 't2', tableNumber: 'T2', seats: 4, floor: 'Dining'),
      RestaurantTable(id: 't3', tableNumber: 'T3', seats: 2, floor: 'Garden'),
    ],
    menu: [
      MenuItem(id: 'paneer', outletId: 'demo', name: 'Paneer Tikka',
        category: 'Starters', price: 240, isVeg: true, imageUrl: '',
        description: 'Tandoor grilled paneer with mint chutney'),
      MenuItem(id: 'biryani', outletId: 'demo', name: 'Veg Biryani',
        category: 'Mains', price: 280, isVeg: true, imageUrl: ''),
      MenuItem(id: 'lime', outletId: 'demo', name: 'Fresh Lime Soda',
        category: 'Drinks', price: 80, isVeg: true, imageUrl: ''),
    ],
  );
  assert(!pos.apiEnabled && pos.menuItems.length == 3 && pos.staffList.length == 5);
  return pos;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final pos = createDemoProvider();
  runApp(ChangeNotifierProvider.value(
    value: pos,
    child: MaterialApp(title: 'Hishobkr Demo', debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme, home: const PinLoginScreen()),
  ));
}

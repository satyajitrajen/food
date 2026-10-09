import 'package:food_pos/models/menu_model.dart';
import 'package:food_pos/models/outlet_model.dart';
import 'package:food_pos/models/staff_model.dart';
import 'package:food_pos/models/table_model.dart';
import 'package:food_pos/providers/pos_provider.dart';

/// Small fixed catalog for widget/unit tests. The app itself ships no demo
/// data; tests load this explicitly.
PosProvider fixtureProvider() => PosProvider()..loadFixture(
      outlets: [
        Outlet(id: 'out-01', name: 'Baner Outlet', terminal: 'Counter 1'),
        Outlet(id: 'out-02', name: 'Kothrud Outlet', terminal: 'Counter 2'),
      ],
      staff: [
        _staff('st-01', 'Rahul Sharma', StaffRole.cashier, '1234', outlet: 'out-01'),
        _staff('st-02', 'Priya Joshi', StaffRole.manager, '9999', outlet: 'out-01'),
        _staff('st-03', 'Vikram Singh', StaffRole.admin, '0000'),
        _staff('st-04', 'Amit Deshmukh', StaffRole.waiter, '1111', outlet: 'out-01'),
        _staff('st-06', 'Chef Sharma', StaffRole.kitchen, '5555', outlet: 'out-01'),
        _staff('st-07', 'Neha Kulkarni', StaffRole.manager, '8888', outlet: 'out-02'),
      ],
      tables: [
        for (var i = 1; i <= 6; i++)
          RestaurantTable(
            id: 't-0$i',
            tableNumber: 'T0$i',
            seats: 4,
            floor: 'Ground Floor',
            status: TableStatus.available,
          ),
      ],
      menu: [
        MenuItem(
          id: 'm-01',
          name: 'Paneer Tikka',
          category: 'Starters',
          price: 280.0,
          isVeg: true,
          imageUrl: '',
          description: 'Char-grilled cottage cheese.',
          isBestseller: true,
        ),
        MenuItem(
          id: 'm-05',
          name: 'Dal Makhani',
          category: 'Main Course',
          price: 240.0,
          isVeg: true,
          imageUrl: '',
          description: 'Slow cooked black lentils.',
        ),
        MenuItem(
          id: 'm-06',
          name: 'Butter Naan',
          category: 'Main Course',
          price: 50.0,
          isVeg: true,
          imageUrl: '',
          description: 'Leavened flatbread with butter.',
        ),
      ],
    );

Staff _staff(String id, String name, StaffRole role, String pin, {String? outlet}) => Staff(
      id: id,
      outletId: outlet,
      name: name,
      role: role,
      pin: pin,
      avatarUrl: '',
      mobile: '',
    );

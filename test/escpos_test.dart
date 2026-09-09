import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/printing/printing.dart';
import 'package:food_pos/core/printing/receipt_builder.dart';
import 'package:food_pos/models/kot_model.dart';
import 'package:food_pos/models/menu_model.dart';
import 'package:food_pos/models/order_model.dart';
import 'package:food_pos/models/settings_model.dart';

RestaurantOrder _order() => RestaurantOrder(
      id: 'ord-1',
      orderNumber: 'ORD-2000',
      orderType: OrderType.dineIn,
      tableNumber: 'T05',
      createdAt: DateTime(2026, 9, 6, 13, 30),
      waiterName: 'Rahul',
      guestCount: 2,
      items: [
        OrderItem(
          id: 'i-1',
          menuItem: MenuItem(
            id: 'm-1',
            name: 'Paneer Tikka',
            category: 'Starters',
            price: 280,
            isVeg: true,
            imageUrl: '',
          ),
          selectedModifiers: [
            ModifierItem(id: 'mo-1', name: 'Extra Mint Chutney', price: 20, isSelected: true),
          ],
          quantity: 2,
          isKOTSent: true,
        ),
      ],
      invoiceNumber: 'INV-2000',
      paidAt: DateTime(2026, 9, 6, 14, 10),
      paymentMethod: 'Cash',
      totalPaid: 700,
    );

void main() {
  test('EscPosBuilder emits init prefix and line feeds', () {
    final bytes = EscPosBuilder().text('hello').build();
    expect(bytes.length, greaterThanOrEqualTo(6));
    expect(bytes[0], 0x1B);
    expect(bytes[1], 0x40);
    expect(bytes.sublist(2, 7), 'hello'.codeUnits);
    expect(bytes.last, 0x0A);
  });

  test('EscPosBuilder align/bold/cut emit ESC/POS commands', () {
    final bytes = EscPosBuilder().align(1).bold(true).text('X').cut().build();
    // init(2) + align(3) + bold(3) + 'X'(1) + LF(1) + cut(4)
    expect(bytes.length, 14);
    expect(bytes.getRange(bytes.length - 4, bytes.length), [0x1D, 0x56, 0x42, 0x00]);
  });

  test('sanitize maps rupee sign and strips non-latin1', () {
    final bytes = EscPosBuilder().text('₹100 • ok').build();
    final s = String.fromCharCodes(bytes.sublist(2, bytes.length - 1));
    expect(s, 'Rs.100 * ok');
  });

  test('receipt bytes contain the invoice and totals', () {
    final settings = RestaurantSettings();
    final bytes = buildReceiptBytes(_order(), settings);
    final s = String.fromCharCodes(bytes);
    expect(s, contains('INV-2000'));
    expect(s, contains('Paneer Tikka'));
    expect(s, contains('Rs.'));
    expect(bytes.last, 0x00); // cut command tail
  });

  test('KOT bytes mark quantity lines and notes', () {
    final kot = KitchenOrderTicket(
      id: 'kot-1',
      kotNumber: 'KOT #1300',
      orderId: 'ord-1',
      tableNumber: 'T05',
      orderType: OrderType.dineIn,
      waiterName: 'Rahul',
      createdAt: DateTime(2026, 9, 6, 13, 30),
      items: [
        OrderItem(
          id: 'i-9',
          menuItem: MenuItem(id: 'm-1', name: 'Dal Makhani', category: '', price: 240, isVeg: true, imageUrl: ''),
          quantity: 3,
          itemNote: 'less spicy',
        ),
      ],
      specialInstructions: 'rush order',
    );
    final s = String.fromCharCodes(buildKotBytes(kot, RestaurantSettings()));
    expect(s, contains('K O T'));
    expect(s, contains('3 x Dal Makhani'));
    expect(s, contains('less spicy'));
    expect(s, contains('rush order'));
  });

  test('printerFromSetting parses host:port and falls back to null printer', () {
    final p = printerFromSetting('192.168.1.50:9100');
    expect(p.name, '192.168.1.50:9100');
    final none = printerFromSetting('EPSON TM-T88VI (Counter)');
    expect(none, isA<NullPrinter>());
  });
}

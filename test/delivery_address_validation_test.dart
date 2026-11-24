import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/validation.dart';

void main() {
  test('cleanSingleLine collapses whitespace and trims', () {
    expect(cleanSingleLine('  12   MG Road,\n Pune  '), '12 MG Road, Pune');
  });

  test('delivery address limits count code points', () {
    expect(validateDeliveryAddress(''), 'Enter the delivery address');
    expect(validateDeliveryAddress('MG'), 'Use at least 5 characters');
    expect(validateDeliveryAddress('12 MG Road'), isNull);
    expect(validateDeliveryAddress('a' * 300), isNull);
    expect(validateDeliveryAddress('a' * 301), 'Use at most 300 characters');
  });

  test('non-Latin addresses with joiners are accepted', () {
    // Marathi uses ZWJ/ZWNJ (U+200D/U+200C) for correct spelling.
    final marathi = 'पुणे ${String.fromCharCode(0x200D)}शिवाजीनगर';
    expect(validateDeliveryAddress(marathi), isNull);
  });

  test('hidden characters are refused', () {
    for (final cp in [0x202E, 0x2066, 0xFEFF, 0x07]) {
      final addr = '12 MG Road${String.fromCharCode(cp)} Pune';
      expect(validateDeliveryAddress(addr), 'Address contains hidden or invalid characters', reason: 'U+${cp.toRadixString(16)}');
    }
  });
}

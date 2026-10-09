import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/format.dart';

void main() {
  group('plural', () {
    test('singular for count 1', () {
      expect(plural(1, 'item'), 'item');
      expect(plural(1, 'order'), 'order');
      expect(plural(1, 'guest'), 'guest');
    });

    test('default +s for counts != 1', () {
      expect(plural(2, 'item'), 'items');
      expect(plural(0, 'item'), 'items');
      expect(plural(12, 'order'), 'orders');
    });

    test('irregular plural word override', () {
      expect(plural(1, 'entry', 'entries'), 'entry');
      expect(plural(3, 'entry', 'entries'), 'entries');
      expect(plural(0, 'entry', 'entries'), 'entries');
    });
  });
}

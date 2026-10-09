import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/format.dart';

void main() {
  group('plural', () {
    test('singular for count 1', () {
      expect(plural(1, 'item'), '1 item');
      expect(plural(1, 'order'), '1 order');
      expect(plural(1, 'guest'), '1 guest');
    });

    test('default +s for counts != 1', () {
      expect(plural(2, 'item'), '2 items');
      expect(plural(0, 'item'), '0 items');
      expect(plural(12, 'order'), '12 orders');
    });

    test('irregular plural word override', () {
      expect(plural(1, 'entry', 'entries'), '1 entry');
      expect(plural(3, 'entry', 'entries'), '3 entries');
      expect(plural(0, 'entry', 'entries'), '0 entries');
    });
  });
}

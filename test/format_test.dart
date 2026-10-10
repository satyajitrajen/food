import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/core/format.dart';

void main() {
  test('formatInr never shows a minus on zero', () {
    expect(formatInr(-0.0), formatInr(0));
    expect(formatInr(-0.001), formatInr(0));
    expect(formatInr(-0.0, whole: true), formatInr(0, whole: true));
    expect(formatInr(0).contains('-'), isFalse);
    expect(formatInr(-5).contains('-'), isTrue);
  });
}

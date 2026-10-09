import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:food_pos/providers/pos_provider.dart';
import '../tool/demo_main.dart' as demo;

void main() {
  testWidgets('demo starts with fictional fixtures and no API', (tester) async {
    demo.main();
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(MaterialApp));
    final pos = context.read<PosProvider>();
    expect(pos.apiEnabled, isFalse);
    expect(pos.currentOutlet.id, 'demo');
    expect(pos.staffList, hasLength(5));
    expect(pos.menuItems, hasLength(3));
    expect(pos.tables, hasLength(3));
    expect(find.text('Demo admin'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    pos.dispose();
  });
}

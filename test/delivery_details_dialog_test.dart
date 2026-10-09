import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/screens/pos_menu/pos_menu_screen.dart';

void main() {
  testWidgets('delivery dialog returns entered details and closes cleanly',
      (tester) async {
    DeliveryDetails? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                result = await DeliveryDetailsDialog.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Customer mobile'), '9876543210');
    await tester.enterText(
        find.widgetWithText(TextField, 'Delivery address'), '12 Main Road');

    await tester.tap(find.text('Start delivery order'));
    // Simulate a viewport change (e.g. the keyboard closing) while the dialog
    // exit animation is still playing: the TextFields are still mounted and
    // must not be backed by disposed controllers during that rebuild.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result?.phone, '9876543210');
    expect(result?.address, '12 Main Road');
    expect(find.text('Start delivery order'), findsNothing);
  });

  testWidgets('delivery dialog cancel returns null and closes cleanly',
      (tester) async {
    DeliveryDetails? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                result = await DeliveryDetailsDialog.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Customer mobile'), '9876543210');

    await tester.tap(find.text('Cancel'));
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.text('Start delivery order'), findsNothing);
  });
}

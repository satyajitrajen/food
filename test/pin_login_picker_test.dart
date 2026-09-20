import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_pos/providers/pos_provider.dart';
import 'package:food_pos/screens/auth/pin_login_screen.dart';
import 'package:provider/provider.dart';

Widget _wrap(PosProvider provider) =>
    ChangeNotifierProvider<PosProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: PinLoginScreen(),
      ),
    );

void main() {
  testWidgets('picker button shows the counter staff count', (tester) async {
    await tester.pumpWidget(_wrap(PosProvider()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Switch profile'), findsOneWidget);
    expect(find.textContaining('6 on this counter'), findsOneWidget);
  });

  testWidgets('sheet searches and switches the signing-in profile',
      (tester) async {
    await tester.pumpWidget(_wrap(PosProvider()));
    await tester.pumpAndSettle();

    final picker = find.textContaining('Switch profile');
    await tester.scrollUntilVisible(picker, 100);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('Who is signing in?'), findsOneWidget);
    expect(find.text('Rahul Sharma'), findsWidgets);

    // Search narrows the scrollable list to the match.
    await tester.enterText(find.byType(TextField), 'Priya');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Priya Joshi'), findsWidgets);
    expect(find.text('1 of 6'), findsOneWidget);

    // Tapping switches the top profile, resets the PIN and closes the sheet.
    await tester.tap(find.text('Priya Joshi'));
    await tester.pumpAndSettle();
    expect(find.text('Who is signing in?'), findsNothing);
    expect(find.text('Priya Joshi'), findsOneWidget);
    expect(find.text('Manager'), findsOneWidget);
  });

  testWidgets('empty search shows the empty state', (tester) async {
    await tester.pumpWidget(_wrap(PosProvider()));
    await tester.pumpAndSettle();

    final picker = find.textContaining('Switch profile');
    await tester.scrollUntilVisible(picker, 100);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz-no-one');
    await tester.pumpAndSettle();
    expect(find.text('No staff match that search.'), findsOneWidget);
  });
}

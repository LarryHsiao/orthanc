import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/quit_dialog.dart';

void main() {
  bool? result;

  Future<void> pumpDialog(WidgetTester tester) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => result = await showQuitDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the confirmation title', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Quit Orthanc?'), findsOneWidget);
  });

  testWidgets('Cancel dismisses without quitting', (tester) async {
    const expected = false;
    await pumpDialog(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Quit Orthanc?'), findsNothing);
    expect(result, expected);
  });

  testWidgets('Quit resolves true', (tester) async {
    const expected = true;
    await pumpDialog(tester);

    await tester.tap(find.text('Quit'));
    await tester.pumpAndSettle();

    expect(find.text('Quit Orthanc?'), findsNothing);
    expect(result, expected);
  });
}

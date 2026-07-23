import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pane_bar.dart';
import 'package:orthanc/session.dart';

void main() {
  Future<Session> pumpPaneBar(WidgetTester tester) async {
    final session = Session(id: 'a', executable: 'cmd.exe');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneBar(
            session: session,
            focused: true,
            canCollapse: false,
            collapsed: false,
          ),
        ),
      ),
    );
    return session;
  }

  Future<void> openRenameMenu(WidgetTester tester) async {
    await tester.tap(
      find.byType(PaneBar),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
  }

  testWidgets('right-click then Rename opens an edit field', (tester) async {
    await pumpPaneBar(tester);

    await openRenameMenu(tester);

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('submitting a name commits it to session.manualName', (
    tester,
  ) async {
    final session = await pumpPaneBar(tester);
    await openRenameMenu(tester);
    const expected = 'api-refactor';

    await tester.enterText(find.byType(TextField), expected);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(session.manualName.value, expected);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('submitting an empty name clears session.manualName', (
    tester,
  ) async {
    final session = await pumpPaneBar(tester);
    session.manualName.value = 'old-name';
    await openRenameMenu(tester);
    const expected = '';

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(session.manualName.value, expected);
  });

  testWidgets('Esc cancels without mutating session.manualName', (
    tester,
  ) async {
    final session = await pumpPaneBar(tester);
    session.manualName.value = 'old-name';
    const expected = 'old-name';
    await openRenameMenu(tester);

    await tester.enterText(find.byType(TextField), 'discarded');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(session.manualName.value, expected);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('field is prefilled with the current manual name when reopened', (
    tester,
  ) async {
    final session = await pumpPaneBar(tester);
    session.manualName.value = 'existing-name';
    const expected = 'existing-name';

    await openRenameMenu(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, expected);
  });
}

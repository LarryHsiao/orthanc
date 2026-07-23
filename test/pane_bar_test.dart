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

  Future<void> rightClickPaneBar(WidgetTester tester) async {
    await tester.tap(
      find.byType(PaneBar),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('right-click opens an edit field, focused for typing', (
    tester,
  ) async {
    await pumpPaneBar(tester);

    await rightClickPaneBar(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.testTextInput.hasAnyClients, isTrue);
  });

  testWidgets('submitting a name commits it to session.manualName', (
    tester,
  ) async {
    final session = await pumpPaneBar(tester);
    await rightClickPaneBar(tester);
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
    await rightClickPaneBar(tester);
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
    await rightClickPaneBar(tester);

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

    await rightClickPaneBar(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, expected);
  });

  testWidgets(
    'steals focus from a sibling node already focused in the same scope',
    (tester) async {
      // Mirrors the real app: PaneView focuses the pane's terminal
      // (session.focusNode) on every pointer-down, including the right-click
      // that opens this field — so by the time the field mounts, something
      // else in the same FocusScope already holds focus. `autofocus` only
      // applies when nothing else does (see workspace_view.dart's
      // _requestFocus doc comment), so this must be won explicitly.
      final rivalFocusNode = FocusNode();
      addTearDown(rivalFocusNode.dispose);
      final session = Session(id: 'a', executable: 'cmd.exe');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Focus(focusNode: rivalFocusNode, child: const SizedBox()),
                PaneBar(
                  session: session,
                  focused: true,
                  canCollapse: false,
                  collapsed: false,
                ),
              ],
            ),
          ),
        ),
      );
      rivalFocusNode.requestFocus();
      await tester.pump();
      expect(rivalFocusNode.hasFocus, isTrue);

      await rightClickPaneBar(tester);

      expect(rivalFocusNode.hasFocus, isFalse);
      expect(tester.testTextInput.hasAnyClients, isTrue);
    },
  );
}

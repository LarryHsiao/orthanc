import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pane_bar.dart';
import 'package:orthanc/session.dart';

void main() {
  // Dracula's blue — light enough that a contrast ink must go dark.
  const lightAccent = Color(0xFFBD93F9);
  // Solarized Dark's blue — dark enough that a contrast ink must go light.
  const darkAccent = Color(0xFF268BD2);

  Future<Session> pumpPaneBar(
    WidgetTester tester, {
    bool focused = true,
    Color accent = lightAccent,
    bool canCollapse = false,
    bool collapsed = false,
  }) async {
    final session = Session(id: 'a', executable: 'cmd.exe');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneBar(
            session: session,
            focused: focused,
            accent: accent,
            canCollapse: canCollapse,
            collapsed: collapsed,
          ),
        ),
      ),
    );
    return session;
  }

  Color? barFill(WidgetTester tester) =>
      tester.widget<Container>(find.byType(Container).first).color;

  Color? titleInk(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text).first).style?.color;

  Future<void> rightClickPaneBar(WidgetTester tester) async {
    await tester.tap(
      find.byType(PaneBar),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('focused bar fills with the accent', (tester) async {
    const expected = lightAccent;

    await pumpPaneBar(tester, focused: true, accent: lightAccent);

    expect(barFill(tester), expected);
  });

  testWidgets('unfocused bar keeps the surface fill, never the accent', (
    tester,
  ) async {
    await pumpPaneBar(tester, focused: false, accent: lightAccent);
    final expected = ThemeData().colorScheme.surfaceContainer;

    expect(barFill(tester), expected);
  });

  testWidgets('a collapsed focused pane still carries the accent fill', (
    tester,
  ) async {
    // A collapsed pane is nothing but its bar — PaneView's border has no
    // body to enclose there, so this fill is its only mark of focus.
    const expected = lightAccent;

    await pumpPaneBar(
      tester,
      focused: true,
      accent: lightAccent,
      canCollapse: true,
      collapsed: true,
    );

    expect(barFill(tester), expected);
  });

  testWidgets('title inks dark on a light accent', (tester) async {
    const expected = Colors.black;

    await pumpPaneBar(tester, focused: true, accent: lightAccent);

    expect(titleInk(tester), expected);
  });

  testWidgets('title inks light on a dark accent', (tester) async {
    const expected = Colors.white;

    await pumpPaneBar(tester, focused: true, accent: darkAccent);

    expect(titleInk(tester), expected);
  });

  testWidgets('unfocused title keeps the surface ink', (tester) async {
    await pumpPaneBar(tester, focused: false, accent: darkAccent);
    final expected = ThemeData().colorScheme.onSurface;

    expect(titleInk(tester), expected);
  });

  testWidgets('collapse glyph takes the same contrast ink when focused', (
    tester,
  ) async {
    const expected = Colors.black;

    await pumpPaneBar(
      tester,
      focused: true,
      accent: lightAccent,
      canCollapse: true,
    );

    final glyph = tester.widget<Text>(find.text('⤢'));
    expect(glyph.style?.color, expected);
  });

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
                  accent: lightAccent,
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

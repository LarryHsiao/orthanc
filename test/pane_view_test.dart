import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pane_view.dart';
import 'package:orthanc/session.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_color_schemes.dart';
import 'package:orthanc/terminal_font_families.dart';
import 'package:xterm/xterm.dart';

void main() {
  final theme = terminalThemeFor(TerminalColorScheme.dracula);

  Future<void> pumpPaneView(
    WidgetTester tester, {
    required bool focused,
    bool collapsed = false,
  }) async {
    final session = Session(id: 'a', executable: 'cmd.exe');
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneView(
            session: session,
            focused: focused,
            onFocus: () {},
            onKeyEvent: (node, event) => KeyEventResult.ignored,
            canCollapse: false,
            collapsed: collapsed,
            theme: theme,
            fontFamily: terminalFontFamilyName(
              TerminalFontFamily.defaultFamily,
            ),
            fontSize: defaultTerminalFontSize,
            onToggleCollapse: () {},
          ),
        ),
      ),
    );
  }

  BoxDecoration focusBorder(WidgetTester tester) =>
      tester
              .widget<DecoratedBox>(find.byKey(PaneView.focusBorderKey))
              .decoration
          as BoxDecoration;

  testWidgets('a focused pane draws the accent border', (tester) async {
    // The literal 0.6, not PaneView.focusAccentStrength — asserting a
    // constant against itself would pass however the design drifted.
    final expected = Color.lerp(theme.background, theme.blue, 0.6);

    await pumpPaneView(tester, focused: true);

    expect(focusBorder(tester).border!.top.color, expected);
  });

  testWidgets('the accent is dimmed, never the palette\'s raw blue', (
    tester,
  ) async {
    final unwanted = theme.blue;

    await pumpPaneView(tester, focused: true);

    expect(focusBorder(tester).border!.top.color, isNot(unwanted));
  });

  testWidgets('the border is drawn at the width the design named', (
    tester,
  ) async {
    // The literal, not PaneView.focusBorderWidth — asserting a constant
    // against itself would pass however the design drifted.
    const expected = 2.0;

    await pumpPaneView(tester, focused: true);

    expect(focusBorder(tester).border!.top.width, expected);
  });

  testWidgets('an unfocused pane draws no border at all', (tester) async {
    await pumpPaneView(tester, focused: false);

    expect(find.byKey(PaneView.focusBorderKey), findsNothing);
  });

  testWidgets('the border does not resize the terminal beneath it', (
    tester,
  ) async {
    await pumpPaneView(tester, focused: false);
    final expected = tester.getSize(find.byType(TerminalView));

    await pumpPaneView(tester, focused: true);

    expect(tester.getSize(find.byType(TerminalView)), expected);
  });

  testWidgets('the border never swallows a pointer meant for the terminal', (
    tester,
  ) async {
    await pumpPaneView(tester, focused: true);
    const expected = true;

    // find.ancestor walks outward from the target, so `.first` is the
    // overlay's own IgnorePointer rather than one of MaterialApp's.
    final overlay = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.byKey(PaneView.focusBorderKey),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );

    expect(overlay.ignoring, expected);
  });
}

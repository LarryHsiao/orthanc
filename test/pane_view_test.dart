import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pane_view.dart';
import 'package:orthanc/session.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_color_schemes.dart';
import 'package:orthanc/terminal_font_families.dart';
import 'package:xterm/xterm.dart';

void main() {
  final theme = terminalThemeFor(TerminalColorScheme.dracula);

  Future<Session> pumpPaneView(
    WidgetTester tester, {
    required bool focused,
    bool collapsed = false,
    Session? session,
  }) async {
    final theSession = session ?? Session(id: 'a', executable: 'cmd.exe');
    addTearDown(theSession.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneView(
            session: theSession,
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
            onExpand: () {},
          ),
        ),
      ),
    );
    return theSession;
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

  BoxDecoration attentionBorder(WidgetTester tester) =>
      tester
              .widget<DecoratedBox>(find.byKey(PaneView.attentionBorderKey))
              .decoration
          as BoxDecoration;

  testWidgets(
    'an unfocused, uncollapsed pane draws the attention halo once the '
    'session needs attention',
    (tester) async {
      final expected = Color.lerp(theme.background, theme.yellow, 0.85);
      final session = await pumpPaneView(tester, focused: false);

      session.needsAttention.value = true;
      await tester.pump();

      expect(attentionBorder(tester).border!.top.color, expected);
    },
  );

  testWidgets('the attention halo clears once the flag clears', (tester) async {
    final session = await pumpPaneView(tester, focused: false);
    session.needsAttention.value = true;
    await tester.pump();

    session.needsAttention.value = false;
    await tester.pump();

    expect(find.byKey(PaneView.attentionBorderKey), findsNothing);
  });

  testWidgets('a collapsed pane draws no attention halo', (tester) async {
    final session = await pumpPaneView(tester, focused: false, collapsed: true);

    session.needsAttention.value = true;
    await tester.pump();

    expect(find.byKey(PaneView.attentionBorderKey), findsNothing);
  });

  testWidgets('the attention accent is dimmed, never the palette\'s raw '
      'yellow', (tester) async {
    final unwanted = theme.yellow;
    final session = await pumpPaneView(tester, focused: false);

    session.needsAttention.value = true;
    await tester.pump();

    expect(attentionBorder(tester).border!.top.color, isNot(unwanted));
  });

  testWidgets('the attention halo is drawn at the width the design named', (
    tester,
  ) async {
    // The literal, not PaneView.attentionBorderWidth — asserting a
    // constant against itself would pass however the design drifted.
    const expected = 3.0;
    final session = await pumpPaneView(tester, focused: false);

    session.needsAttention.value = true;
    await tester.pump();

    expect(attentionBorder(tester).border!.top.width, expected);
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

  Future<void> rightClick(WidgetTester tester) async {
    await tester.tap(
      find.byType(TerminalView),
      buttons: kSecondaryButton,
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  // find.widgetWithText(PopupMenuItem, label) matches by exact runtimeType,
  // which never equals the generic PopupMenuItem<_ClipboardMenuAction> the
  // menu actually builds — a predicate's `is` check matches any type
  // argument, the way a plain `is PopupMenuItem` test would in code.
  PopupMenuItem menuItem(WidgetTester tester, String label) =>
      tester.widget(
            find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            ),
          )
          as PopupMenuItem;

  group('right-click Copy/Paste menu', () {
    // flutter_test does not mock the clipboard channel on its own — an
    // unmocked Clipboard.getData() call hangs until the test's own 10-minute
    // timeout, rather than returning null. A minimal in-memory handler
    // stands in for the OS clipboard for the tests in this group.
    String? clipboardText;

    setUp(() {
      clipboardText = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            switch (call.method) {
              case 'Clipboard.setData':
                clipboardText = (call.arguments as Map)['text'] as String?;
                return null;
              case 'Clipboard.getData':
                return clipboardText == null ? null : {'text': clipboardText};
              case 'Clipboard.hasStrings':
                return {'value': clipboardText != null};
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('right-click opens a menu with Copy and Paste', (tester) async {
      await pumpPaneView(tester, focused: true);

      await rightClick(tester);

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('Copy is disabled without a selection', (tester) async {
      const expected = false;
      await pumpPaneView(tester, focused: true);

      await rightClick(tester);

      expect(menuItem(tester, 'Copy').enabled, expected);
    });

    testWidgets('Copy is enabled with a selection', (tester) async {
      const expected = true;
      final session = Session(id: 'a', executable: 'cmd.exe');
      session.terminal.write('hello');
      session.terminalController.setSelection(
        session.terminal.buffer.createAnchor(0, 0),
        session.terminal.buffer.createAnchor(5, 0),
      );

      await pumpPaneView(tester, focused: true, session: session);
      await rightClick(tester);

      expect(menuItem(tester, 'Copy').enabled, expected);
    });

    testWidgets('selecting Copy sends the selected text to the clipboard', (
      tester,
    ) async {
      const expected = 'hello';
      final session = Session(id: 'a', executable: 'cmd.exe');
      session.terminal.write('hello');
      session.terminalController.setSelection(
        session.terminal.buffer.createAnchor(0, 0),
        session.terminal.buffer.createAnchor(5, 0),
      );
      await pumpPaneView(tester, focused: true, session: session);
      await rightClick(tester);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboard?.text, expected);
    });

    testWidgets('selecting Copy leaves the selection in place', (tester) async {
      // Matches xterm's own keyboard Copy, which never clears it either —
      // the two Copy paths should read the same afterward.
      const expected = isNotNull;
      final session = Session(id: 'a', executable: 'cmd.exe');
      session.terminal.write('hello');
      session.terminalController.setSelection(
        session.terminal.buffer.createAnchor(0, 0),
        session.terminal.buffer.createAnchor(5, 0),
      );
      await pumpPaneView(tester, focused: true, session: session);
      await rightClick(tester);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(session.terminalController.selection, expected);
    });

    testWidgets('selecting Paste writes the clipboard text into the terminal', (
      tester,
    ) async {
      const expected = 'pasted!';
      await Clipboard.setData(const ClipboardData(text: expected));
      final session = Session(id: 'a', executable: 'cmd.exe');
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;
      await pumpPaneView(tester, focused: true, session: session);
      await rightClick(tester);

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(outputs, [expected]);
    });

    testWidgets('Paste does nothing when the clipboard holds no text', (
      tester,
    ) async {
      const expected = <String>[];
      await Clipboard.setData(const ClipboardData(text: ''));
      final session = Session(id: 'a', executable: 'cmd.exe');
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;
      await pumpPaneView(tester, focused: true, session: session);
      await rightClick(tester);

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();

      expect(outputs, expected);
    });
  });
}

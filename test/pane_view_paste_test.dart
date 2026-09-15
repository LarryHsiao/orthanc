import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pane_view.dart';
import 'package:orthanc/session.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_color_schemes.dart';
import 'package:orthanc/terminal_font_families.dart';

/// The one file that mocks the `pasteboard` channel — every other test that
/// exercises `pasteIntoSession` reaches it through the injected `readFiles`
/// seam instead, precisely to keep this channel-mocking surface small. This
/// file needs the real channel, because it is what proves the Cmd+V wiring
/// itself, not just what `pasteIntoSession` does once called.
void main() {
  final theme = terminalThemeFor(TerminalColorScheme.dracula);
  String? clipboardText;
  List<String> pasteboardFiles = [];

  // pasteIntoSession's real call site (PaneView's Actions wrapper) passes
  // no fileExists override — this is the one test file that exercises the
  // real File.existsSync gate end to end, so a path standing in for "a
  // file on the clipboard" must actually exist on disk, not just be named.
  late Directory tempDir;
  late File realFile;

  setUp(() {
    clipboardText = null;
    pasteboardFiles = [];
    tempDir = Directory.systemTemp.createTempSync('orthanc-paste-test-');
    realFile = File('${tempDir.path}/shot.png')..writeAsBytesSync([0]);
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pasteboard'), (
          call,
        ) async {
          if (call.method == 'files') return pasteboardFiles;
          return null;
        });
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pasteboard'), null);
  });

  /// Runs [body] with `debugDefaultTargetPlatformOverride` set to macOS —
  /// `defaultTerminalShortcuts` (the fork's own default map) switches on
  /// `defaultTargetPlatform`, which `flutter_test` defaults to Android, so
  /// without this override there is no Cmd+V entry to rebind at all.
  ///
  /// The reset happens in a `finally` clause wrapping [body] directly,
  /// *inside* the `testWidgets` callback — not via `tearDown()` or
  /// `addTearDown()`. Both of those fire only after the whole test,
  /// including Flutter's own end-of-test invariant check, has already
  /// resolved (confirmed by reading `testWidgets`'s own source: the
  /// function it hands to `package:test`'s `test()` is exactly the one that
  /// calls `binding.runTest(...)` and returns its future, so nothing
  /// registered as a teardown runs before that future — and thus the
  /// invariant check inside it — completes). A `tearDown`-based reset was
  /// tried first and failed with "The value of a foundation debug variable
  /// was changed by the test" on every test in this file; this is why.
  void testMacOSWidget(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<Session> pumpPaneView(WidgetTester tester, {Session? session}) async {
    final theSession = session ?? Session(id: 'a', executable: '/bin/zsh');
    addTearDown(theSession.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneView(
            session: theSession,
            focused: true,
            onFocus: () {},
            onKeyEvent: (node, event) => KeyEventResult.ignored,
            canCollapse: false,
            collapsed: false,
            theme: theme,
            fontFamily: terminalFontFamilyName(
              TerminalFontFamily.defaultFamily,
            ),
            fontSize: defaultTerminalFontSize,
            onToggleCollapse: () {},
            onExpand: () {},
            canDrag: false,
            onDragStart: (_) {},
            onDragUpdate: (_, _) {},
            onDragEnd: (_) {},
            isDropTarget: false,
            isBeingDragged: false,
            dropSide: null,
            isFileDropTarget: false,
          ),
        ),
      ),
    );
    // Nothing autofocuses the terminal on its own — Actions resolution
    // starts from primaryFocus, so without this, Cmd+V has no focused
    // context to resolve an action from at all.
    theSession.focusNode.requestFocus();
    await tester.pump();
    return theSession;
  }

  Future<void> pressCmd(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  group('Cmd+V', () {
    testMacOSWidget('with a file writes an @-reference when a program owns '
        'the pane', (tester) async {
      final session = await pumpPaneView(
        tester,
        session: Session(id: 'a', executable: '/bin/zsh'),
      );
      final expected = ['@${realFile.path}'];
      session.name.value = 'Compacting…';
      pasteboardFiles = [realFile.path];
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pressCmd(tester, LogicalKeyboardKey.keyV);

      expect(outputs, expected);
    });

    testMacOSWidget('with a file writes a bare quoted path when the shell '
        'sits idle', (tester) async {
      final session = await pumpPaneView(
        tester,
        session: Session(id: 'a', executable: '/bin/zsh'),
      );
      final expected = ["'${realFile.path}'"];
      session.name.value = tempDir.path;
      pasteboardFiles = [realFile.path];
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pressCmd(tester, LogicalKeyboardKey.keyV);

      expect(outputs, expected);
    });

    testMacOSWidget('with no file on the clipboard still pastes text', (
      tester,
    ) async {
      const expected = ['pasted!'];
      final session = await pumpPaneView(tester);
      clipboardText = 'pasted!';
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pressCmd(tester, LogicalKeyboardKey.keyV);

      expect(outputs, expected);
    });

    testMacOSWidget('prefers a file over text when the clipboard holds both', (
      tester,
    ) async {
      final session = await pumpPaneView(
        tester,
        session: Session(id: 'a', executable: '/bin/zsh'),
      );
      final expected = ['@${realFile.path}'];
      session.name.value = 'Compacting…';
      pasteboardFiles = [realFile.path];
      clipboardText = 'ignored';
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pressCmd(tester, LogicalKeyboardKey.keyV);

      expect(outputs, expected);
    });

    testMacOSWidget('with nothing to paste writes nothing to the pty', (
      tester,
    ) async {
      const expected = <String>[];
      final session = await pumpPaneView(tester);
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pressCmd(tester, LogicalKeyboardKey.keyV);

      expect(outputs, expected);
    });

    testMacOSWidget("a web link's path component is not mistaken for a file", (
      tester,
    ) async {
      // pastedFilePaths rejects '/a/b' because nothing exists at that
      // path (a temp dir has no such file) — the same shape the real
      // Safari case takes, per pasted_file_paths.dart's own doc.
      const expected = ['https://example.com/a/b'];
      final session = await pumpPaneView(tester);
      pasteboardFiles = ['/a/b'];
      clipboardText = 'https://example.com/a/b';
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pressCmd(tester, LogicalKeyboardKey.keyV);

      expect(outputs, expected);
    });
  });

  group('Cmd+V regressions — the point of this file', () {
    testMacOSWidget('Cmd+C still copies the selection', (tester) async {
      const expected = 'hello';
      final session = await pumpPaneView(tester);
      session.terminal.write('hello');
      session.terminalController.setSelection(
        session.terminal.buffer.createAnchor(0, 0),
        session.terminal.buffer.createAnchor(5, 0),
      );

      await pressCmd(tester, LogicalKeyboardKey.keyC);

      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboard?.text, expected);
    });

    testMacOSWidget('Cmd+A still selects all', (tester) async {
      const expected = isNotNull;
      final session = await pumpPaneView(tester);
      session.terminal.write('hello');

      await pressCmd(tester, LogicalKeyboardKey.keyA);

      expect(session.terminalController.selection, expected);
    });

    testMacOSWidget('an unrelated key still reaches the terminal', (
      tester,
    ) async {
      // A control key, not a printable letter: a letter's widget-test key
      // event does not reliably reach _handleKeyEvent's raw keyInput path
      // the same way a real hardware keystroke would, since CustomTextEdit
      // may route printable input through IME composition instead. Arrow
      // keys carry no such ambiguity and are definitely not in
      // defaultTerminalShortcuts, so this still proves the rebuilt
      // shortcuts map swallows nothing it shouldn't.
      final session = await pumpPaneView(tester);
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(outputs, isNotEmpty);
    });
  });
}

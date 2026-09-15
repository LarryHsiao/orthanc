import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/session.dart';
import 'package:orthanc/session_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test does not mock the clipboard channel on its own — an
  // unmocked Clipboard.getData() call hangs until the test's own timeout,
  // rather than returning null. A minimal in-memory handler stands in for
  // the OS clipboard, the same shape as pane_view_test.dart's own mock.
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

  group('copySelection', () {
    test('puts the selected text on the clipboard', () async {
      const expected = 'hello';
      final session = Session(id: 'a', executable: 'cmd.exe');
      addTearDown(session.dispose);
      session.terminal.write('hello');
      session.terminalController.setSelection(
        session.terminal.buffer.createAnchor(0, 0),
        session.terminal.buffer.createAnchor(5, 0),
      );

      copySelection(session);

      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboard?.text, expected);
    });

    test('leaves the selection in place', () {
      const expected = isNotNull;
      final session = Session(id: 'a', executable: 'cmd.exe');
      addTearDown(session.dispose);
      session.terminal.write('hello');
      session.terminalController.setSelection(
        session.terminal.buffer.createAnchor(0, 0),
        session.terminal.buffer.createAnchor(5, 0),
      );

      copySelection(session);

      expect(session.terminalController.selection, expected);
    });

    test('does nothing without a selection', () async {
      const expected = null;
      final session = Session(id: 'a', executable: 'cmd.exe');
      addTearDown(session.dispose);

      copySelection(session);

      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboard?.text, expected);
    });
  });

  group('pasteIntoSession', () {
    test('writes the clipboard text into the terminal', () async {
      const expected = ['pasted!'];
      await Clipboard.setData(const ClipboardData(text: 'pasted!'));
      final session = Session(id: 'a', executable: 'cmd.exe');
      addTearDown(session.dispose);
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pasteIntoSession(
        session,
        isWindows: false,
        readFiles: () async => [],
      );

      expect(outputs, expected);
    });

    test('does nothing when the clipboard holds no text', () async {
      const expected = <String>[];
      await Clipboard.setData(const ClipboardData(text: ''));
      final session = Session(id: 'a', executable: 'cmd.exe');
      addTearDown(session.dispose);
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pasteIntoSession(
        session,
        isWindows: false,
        readFiles: () async => [],
      );

      expect(outputs, expected);
    });

    test('clears the selection', () async {
      const expected = null;
      await Clipboard.setData(const ClipboardData(text: 'pasted!'));
      final session = Session(id: 'a', executable: 'cmd.exe');
      addTearDown(session.dispose);
      session.terminal.write('hello');
      session.terminalController.setSelection(
        session.terminal.buffer.createAnchor(0, 0),
        session.terminal.buffer.createAnchor(5, 0),
      );

      await pasteIntoSession(
        session,
        isWindows: false,
        readFiles: () async => [],
      );

      expect(session.terminalController.selection, expected);
    });

    test('prefers a file on the clipboard over its text', () async {
      const expected = ['@/Users/x/shot.png'];
      await Clipboard.setData(const ClipboardData(text: 'ignored'));
      final session = Session(id: 'a', executable: '/bin/zsh');
      addTearDown(session.dispose);
      session.name.value = 'Compacting…'; // a program owns the title
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pasteIntoSession(
        session,
        isWindows: false,
        readFiles: () async => ['/Users/x/shot.png'],
        fileExists: (_) => true,
      );

      expect(outputs, expected);
    });

    test('falls back to text when no candidate file checks out', () async {
      // The Safari case: a "file" whose path doesn't exist on disk is
      // rejected by pastedFilePaths, so the clipboard's text is used.
      const expected = ['https://example.com/a/b'];
      await Clipboard.setData(
        const ClipboardData(text: 'https://example.com/a/b'),
      );
      final session = Session(id: 'a', executable: '/bin/zsh');
      addTearDown(session.dispose);
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pasteIntoSession(
        session,
        isWindows: false,
        readFiles: () async => ['/a/b'],
        fileExists: (_) => false,
      );

      expect(outputs, expected);
    });

    test('clears the selection on a file paste too', () async {
      const expected = null;
      final session = Session(id: 'a', executable: '/bin/zsh');
      addTearDown(session.dispose);
      session.name.value = '/Users/x';
      session.terminal.write('hello');
      session.terminalController.setSelection(
        session.terminal.buffer.createAnchor(0, 0),
        session.terminal.buffer.createAnchor(5, 0),
      );

      await pasteIntoSession(
        session,
        isWindows: false,
        readFiles: () async => ['/Users/x/shot.png'],
        fileExists: (_) => true,
      );

      expect(session.terminalController.selection, expected);
    });

    test('space-joins two clipboard files under cmd.exe', () async {
      const expected = [r'"C:\a.txt" "C:\b.txt"'];
      final session = Session(id: 'a', executable: 'cmd.exe');
      addTearDown(session.dispose);
      session.name.value = r'C:\Users\x';
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      await pasteIntoSession(
        session,
        isWindows: true,
        readFiles: () async => [r'C:\a.txt', r'C:\b.txt'],
        fileExists: (_) => true,
      );

      expect(outputs, expected);
    });
  });
}

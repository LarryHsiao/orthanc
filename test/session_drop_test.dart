import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/session.dart';
import 'package:orthanc/session_drop.dart';

void main() {
  group('dropPathsInto', () {
    test('writes a bare quoted path when the shell sits idle', () {
      const expected = ["'/Users/x/shot.png'"];
      final session = Session(id: 'a', executable: '/bin/zsh');
      addTearDown(session.dispose);
      session.name.value = '/Users/x'; // the shell's own prompt announcement
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      dropPathsInto(session, ['/Users/x/shot.png'], isWindows: false);

      expect(outputs, expected);
    });

    test('writes an @-reference when a program owns the title', () {
      const expected = ['@/Users/x/shot.png'];
      final session = Session(id: 'a', executable: '/bin/zsh');
      addTearDown(session.dispose);
      session.name.value = 'Compacting…'; // not a path — a program set it
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      dropPathsInto(session, ['/Users/x/shot.png'], isWindows: false);

      expect(outputs, expected);
    });

    test('space-joins several paths under cmd.exe on Windows', () {
      const expected = [r'"C:\a.txt" "C:\b.txt"'];
      final session = Session(id: 'a', executable: 'cmd.exe');
      addTearDown(session.dispose);
      session.name.value = r'C:\Users\x';
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      dropPathsInto(session, [r'C:\a.txt', r'C:\b.txt'], isWindows: true);

      expect(outputs, expected);
    });

    test('does not treat a "cmd"-named executable as cmd.exe off Windows', () {
      // isCmdShell is a bare basename match — Windows-gated here so a
      // POSIX binary someone names literally `cmd` isn't mistaken for
      // the real thing. Newline-joined, single-quoted: the POSIX form,
      // not cmd's, even though the executable's name matches.
      const expected = ["'/tmp/a.txt'\n'/tmp/b.txt'"];
      final session = Session(id: 'a', executable: 'cmd');
      addTearDown(session.dispose);
      session.name.value = '/tmp';
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      dropPathsInto(session, ['/tmp/a.txt', '/tmp/b.txt'], isWindows: false);

      expect(outputs, expected);
    });

    test('newline-joins several paths outside cmd.exe', () {
      const expected = ["'/Users/x/a.txt'\n'/Users/x/b.txt'"];
      final session = Session(id: 'a', executable: '/bin/zsh');
      addTearDown(session.dispose);
      session.name.value = '/Users/x';
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      dropPathsInto(session, [
        '/Users/x/a.txt',
        '/Users/x/b.txt',
      ], isWindows: false);

      expect(outputs, expected);
    });

    test('does nothing with an empty path list', () {
      const expected = <String>[];
      final session = Session(id: 'a', executable: '/bin/zsh');
      addTearDown(session.dispose);
      session.name.value = '/Users/x';
      final outputs = <String>[];
      session.terminal.onOutput = outputs.add;

      dropPathsInto(session, [], isWindows: false);

      expect(outputs, expected);
    });

    test('clears the selection', () {
      const expected = null;
      final session = Session(id: 'a', executable: '/bin/zsh');
      addTearDown(session.dispose);
      session.name.value = '/Users/x';
      session.terminal.write('hello');
      session.terminalController.setSelection(
        session.terminal.buffer.createAnchor(0, 0),
        session.terminal.buffer.createAnchor(5, 0),
      );

      dropPathsInto(session, ['/Users/x/shot.png'], isWindows: false);

      expect(session.terminalController.selection, expected);
    });
  });
}

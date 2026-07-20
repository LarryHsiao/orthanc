import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/claude_command.dart';

void main() {
  test('lists native-installer and Homebrew paths on macOS/Linux', () {
    final expected = [
      '/home/larry/.local/bin/claude',
      '/opt/homebrew/bin/claude',
      '/usr/local/bin/claude',
    ];
    final result = knownClaudePaths(home: '/home/larry', isWindows: false);
    expect(result, expected);
  });

  test('lists native-installer and npm paths on Windows', () {
    final expected = [
      r'C:\Users\larry\.local\bin\claude.exe',
      r'C:\Users\larry\AppData\Roaming\npm\claude.cmd',
    ];
    final result = knownClaudePaths(home: r'C:\Users\larry', isWindows: true);
    expect(result, expected);
  });

  test('resolves to the first existing known path', () {
    final expected = '/opt/homebrew/bin/claude';
    final result = resolveClaudeCommand(
      home: '/home/larry',
      isWindows: false,
      exists: (path) => path == '/opt/homebrew/bin/claude',
    );
    expect(result, expected);
  });

  test('falls back to the bare command when no known path exists', () {
    final expected = 'claude';
    final result = resolveClaudeCommand(
      home: '/home/larry',
      isWindows: false,
      exists: (path) => false,
    );
    expect(result, expected);
  });
}

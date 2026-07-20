import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/shell_command.dart';

void main() {
  test('returns cmd.exe on Windows', () {
    final expected = 'cmd.exe';
    final result = shellCommand(isWindows: true, environment: const {});
    expect(result, expected);
  });

  test('returns the SHELL environment variable on non-Windows when set', () {
    final expected = '/bin/zsh';
    final result = shellCommand(
      isWindows: false,
      environment: const {'SHELL': '/bin/zsh'},
    );
    expect(result, expected);
  });

  test('falls back to bash on non-Windows when SHELL is unset', () {
    final expected = 'bash';
    final result = shellCommand(isWindows: false, environment: const {});
    expect(result, expected);
  });
}

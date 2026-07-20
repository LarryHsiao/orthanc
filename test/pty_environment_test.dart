import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pty_environment.dart';

void main() {
  test('forwards the whole environment on Windows', () {
    final expected = {
      'SystemRoot': r'C:\Windows',
      'PATH': r'C:\Users\larry\.local\bin',
      'COMSPEC': r'C:\Windows\system32\cmd.exe',
    };

    final result = ptyEnvironment(isWindows: true, environment: expected);

    expect(result, expected);
  });

  test('leaves TERM and LANG to the pty on Windows', () {
    final expected = {'SystemRoot': r'C:\Windows'};

    final result = ptyEnvironment(
      isWindows: true,
      environment: const {
        'SystemRoot': r'C:\Windows',
        'TERM': 'cygwin',
        'LANG': 'C',
      },
    );

    expect(result, expected);
  });

  test('returns only COLORTERM on non-Windows when it is set', () {
    final expected = {'COLORTERM': 'truecolor'};

    final result = ptyEnvironment(
      isWindows: false,
      environment: const {'COLORTERM': 'truecolor', 'SHELL': '/bin/zsh'},
    );

    expect(result, expected);
  });

  test('returns null on non-Windows when COLORTERM is unset', () {
    const expected = null;

    final result = ptyEnvironment(
      isWindows: false,
      environment: const {'SHELL': '/bin/zsh'},
    );

    expect(result, expected);
  });
}

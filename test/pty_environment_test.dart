import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pty_environment.dart';

void main() {
  test('forwards the whole environment on Windows', () {
    final input = {
      'SystemRoot': r'C:\Windows',
      'PATH': r'C:\Users\larry\.local\bin',
      'COMSPEC': r'C:\Windows\system32\cmd.exe',
    };
    final expected = {...input, 'FORCE_HYPERLINK': '1'};

    final result = ptyEnvironment(isWindows: true, environment: input);

    expect(result, expected);
  });

  test('leaves TERM and LANG to the pty on Windows', () {
    final expected = {'SystemRoot': r'C:\Windows', 'FORCE_HYPERLINK': '1'};

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

  test('withholds NO_COLOR on Windows, as macOS already does', () {
    final expected = {'SystemRoot': r'C:\Windows', 'FORCE_HYPERLINK': '1'};

    final result = ptyEnvironment(
      isWindows: true,
      environment: const {'SystemRoot': r'C:\Windows', 'NO_COLOR': '1'},
    );

    expect(result, expected);
  });

  test('withholds the same names whatever their case, since Windows treats '
      'environment variable names case-insensitively', () {
    final expected = {'SystemRoot': r'C:\Windows', 'FORCE_HYPERLINK': '1'};

    final result = ptyEnvironment(
      isWindows: true,
      environment: const {
        'SystemRoot': r'C:\Windows',
        'term': 'cygwin',
        'Lang': 'C',
        'No_Color': '1',
      },
    );

    expect(result, expected);
  });

  test('keeps variables that merely contain a withheld name', () {
    final input = {
      'TERMINAL': 'wezterm',
      'LANGUAGE': 'en_US',
      'NO_COLOR_SCHEME': 'dark',
    };
    final expected = {...input, 'FORCE_HYPERLINK': '1'};

    final result = ptyEnvironment(isWindows: true, environment: input);

    expect(result, expected);
  });

  test('returns COLORTERM and FORCE_HYPERLINK on non-Windows when COLORTERM '
      'is set', () {
    final expected = {'COLORTERM': 'truecolor', 'FORCE_HYPERLINK': '1'};

    final result = ptyEnvironment(
      isWindows: false,
      environment: const {'COLORTERM': 'truecolor', 'SHELL': '/bin/zsh'},
    );

    expect(result, expected);
  });

  test(
    'returns just FORCE_HYPERLINK on non-Windows when COLORTERM is unset',
    () {
      const expected = {'FORCE_HYPERLINK': '1'};

      final result = ptyEnvironment(
        isWindows: false,
        environment: const {'SHELL': '/bin/zsh'},
      );

      expect(result, expected);
    },
  );

  test(
    'always forces hyperlink support, since Orthanc never identifies itself '
    'via TERM_PROGRAM or VTE_VERSION the way a hyperlink-aware CLI checks for',
    () {
      const expected = '1';

      final result = ptyEnvironment(isWindows: false, environment: const {});

      expect(result['FORCE_HYPERLINK'], expected);
    },
  );
}

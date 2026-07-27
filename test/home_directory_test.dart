import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/home_directory.dart';

void main() {
  group('Windows', () {
    test('prefers HOME when it names a path Windows can use', () {
      const expected = r'D:\elsewhere';

      final result = homeDirectory(
        isWindows: true,
        environment: const {
          'HOME': r'D:\elsewhere',
          'USERPROFILE': r'C:\Users\larry',
        },
      );

      expect(result, expected);
    });

    test('falls back to USERPROFILE when HOME is MSYS-style', () {
      const expected = r'C:\Users\larry';

      final result = homeDirectory(
        isWindows: true,
        environment: const {
          'HOME': '/c/Users/larry',
          'USERPROFILE': r'C:\Users\larry',
        },
      );

      expect(result, expected);
    });

    test('falls back to USERPROFILE when HOME is absent entirely', () {
      const expected = r'C:\Users\larry';

      final result = homeDirectory(
        isWindows: true,
        environment: const {'USERPROFILE': r'C:\Users\larry'},
      );

      expect(result, expected);
    });

    test('ignores an MSYS-style HOME when USERPROFILE is absent', () {
      const expected = null;

      final result = homeDirectory(
        isWindows: true,
        environment: const {'HOME': '/c/Users/larry'},
      );

      expect(result, expected);
    });

    test('falls back to HOME when it names a drive-letter path', () {
      const expected = r'D:\home\larry';

      final result = homeDirectory(
        isWindows: true,
        environment: const {'HOME': r'D:\home\larry'},
      );

      expect(result, expected);
    });

    test('falls back to HOME when it names a UNC path', () {
      const expected = r'\\fileserver\profiles\larry';

      final result = homeDirectory(
        isWindows: true,
        environment: const {'HOME': r'\\fileserver\profiles\larry'},
      );

      expect(result, expected);
    });

    test('returns null when neither is set', () {
      const expected = null;

      final result = homeDirectory(
        isWindows: true,
        environment: const {'PATH': r'C:\Windows'},
      );

      expect(result, expected);
    });
  });

  group('non-Windows', () {
    test('returns HOME', () {
      const expected = '/Users/larry';

      final result = homeDirectory(
        isWindows: false,
        environment: const {'HOME': '/Users/larry'},
      );

      expect(result, expected);
    });

    test('ignores USERPROFILE', () {
      const expected = null;

      final result = homeDirectory(
        isWindows: false,
        environment: const {'USERPROFILE': r'C:\Users\larry'},
      );

      expect(result, expected);
    });

    test('returns null when HOME is unset', () {
      const expected = null;

      final result = homeDirectory(
        isWindows: false,
        environment: const {'SHELL': '/bin/zsh'},
      );

      expect(result, expected);
    });
  });
}

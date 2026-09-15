import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/dropped_paths_text.dart';

void main() {
  group('droppedPathsText', () {
    test('quotes a plain POSIX path with single quotes', () {
      const expected = "'/Users/x/shot.png'";

      final result = droppedPathsText(
        paths: ['/Users/x/shot.png'],
        atReferenced: false,
        isWindows: false,
        isCmd: false,
      );

      expect(result, expected);
    });

    test('does not escape a space inside single-quoted POSIX path', () {
      const expected = "'/Users/x/My File.txt'";

      final result = droppedPathsText(
        paths: ['/Users/x/My File.txt'],
        atReferenced: false,
        isWindows: false,
        isCmd: false,
      );

      expect(result, expected);
    });

    test('escapes an embedded apostrophe in a POSIX path', () {
      const expected = r"'/Users/x/it'\''s.txt'";

      final result = droppedPathsText(
        paths: ["/Users/x/it's.txt"],
        atReferenced: false,
        isWindows: false,
        isCmd: false,
      );

      expect(result, expected);
    });

    test('leaves non-ASCII bytes untouched inside single quotes', () {
      const expected = "'/Users/x/日本語.txt'";

      final result = droppedPathsText(
        paths: ['/Users/x/日本語.txt'],
        atReferenced: false,
        isWindows: false,
        isCmd: false,
      );

      expect(result, expected);
    });

    test('double-quotes a bare path for cmd.exe', () {
      const expected = r'"C:\Users\x\shot.png"';

      final result = droppedPathsText(
        paths: [r'C:\Users\x\shot.png'],
        atReferenced: false,
        isWindows: true,
        isCmd: true,
      );

      expect(result, expected);
    });

    test('writes an @-reference unquoted on POSIX', () {
      const expected = '@/Users/x/shot.png';

      final result = droppedPathsText(
        paths: ['/Users/x/shot.png'],
        atReferenced: true,
        isWindows: false,
        isCmd: false,
      );

      expect(result, expected);
    });

    test('backslash-escapes a space in an @-referenced POSIX path', () {
      const expected = r'@/Users/x/My\ File.txt';

      final result = droppedPathsText(
        paths: ['/Users/x/My File.txt'],
        atReferenced: true,
        isWindows: false,
        isCmd: false,
      );

      expect(result, expected);
    });

    test('leaves an @-referenced Windows path verbatim', () {
      const expected = r'@C:\Users\x\My File.txt';

      final result = droppedPathsText(
        paths: [r'C:\Users\x\My File.txt'],
        atReferenced: true,
        isWindows: true,
        isCmd: false,
      );

      expect(result, expected);
    });

    test('joins several paths with newlines outside cmd', () {
      const expected = "'/Users/x/a.txt'\n'/Users/x/b.txt'";

      final result = droppedPathsText(
        paths: ['/Users/x/a.txt', '/Users/x/b.txt'],
        atReferenced: false,
        isWindows: false,
        isCmd: false,
      );

      expect(result, expected);
    });

    test('joins several paths with spaces under cmd', () {
      const expected = r'"C:\a.txt" "C:\b.txt"';

      final result = droppedPathsText(
        paths: [r'C:\a.txt', r'C:\b.txt'],
        atReferenced: false,
        isWindows: true,
        isCmd: true,
      );

      expect(result, expected);
    });

    test('space-joins @-referenced paths under cmd too', () {
      const expected = r'@C:\a.txt @C:\b.txt';

      final result = droppedPathsText(
        paths: [r'C:\a.txt', r'C:\b.txt'],
        atReferenced: true,
        isWindows: true,
        isCmd: true,
      );

      expect(result, expected);
    });

    test('returns an empty string for no paths', () {
      const expected = '';

      final result = droppedPathsText(
        paths: [],
        atReferenced: false,
        isWindows: false,
        isCmd: false,
      );

      expect(result, expected);
    });
  });
}

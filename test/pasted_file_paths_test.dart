import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pasted_file_paths.dart';

void main() {
  group('pastedFilePaths', () {
    test('keeps an absolute POSIX path that exists', () {
      const expected = ['/Users/x/shot.png'];

      final result = pastedFilePaths([
        '/Users/x/shot.png',
      ], exists: (_) => true);

      expect(result, expected);
    });

    test('drops a relative path even if it "exists"', () {
      const expected = <String>[];

      final result = pastedFilePaths(['shot.png'], exists: (_) => true);

      expect(result, expected);
    });

    test('drops an absolute path that does not exist on disk', () {
      // The Safari case: a copied web link's URL path component looks
      // absolute but names nothing real.
      const expected = <String>[];

      final result = pastedFilePaths(['/a/b'], exists: (_) => false);

      expect(result, expected);
    });

    test('drops an empty string', () {
      const expected = <String>[];

      final result = pastedFilePaths([''], exists: (_) => true);

      expect(result, expected);
    });

    test('keeps a Windows drive path that exists', () {
      const expected = [r'C:\Users\x\shot.png'];

      final result = pastedFilePaths([
        r'C:\Users\x\shot.png',
      ], exists: (p) => p == r'C:\Users\x\shot.png');

      expect(result, expected);
    });

    test('returns an empty list for an empty input', () {
      const expected = <String>[];

      final result = pastedFilePaths([], exists: (_) => true);

      expect(result, expected);
    });

    test('preserves order across several survivors', () {
      const expected = ['/a.txt', '/c.txt'];

      final result = pastedFilePaths([
        '/a.txt',
        '/b.txt',
        '/c.txt',
      ], exists: (p) => p != '/b.txt');

      expect(result, expected);
    });
  });
}

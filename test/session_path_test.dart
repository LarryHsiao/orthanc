import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/session_path.dart';

void main() {
  test('a POSIX path is returned as-is', () {
    const expected = '/Users/larry/orthanc';

    final result = sessionPath('/Users/larry/orthanc');

    expect(result, expected);
  });

  test('a Windows drive path is returned as-is', () {
    const expected = r'C:\Users\larry';

    final result = sessionPath(r'C:\Users\larry');

    expect(result, expected);
  });

  test('a Git Bash path is returned as-is', () {
    const expected = '/c/Users/larry';

    final result = sessionPath('/c/Users/larry');

    expect(result, expected);
  });

  test('a program title that is not a path returns null', () {
    const expected = null;

    final result = sessionPath('Compacting…');

    expect(result, expected);
  });

  test('an empty name returns null', () {
    const expected = null;

    final result = sessionPath('');

    expect(result, expected);
  });
}

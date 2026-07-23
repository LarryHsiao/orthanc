import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings_validation.dart';

void main() {
  test('a blank path is always valid', () {
    const expected = true;

    final result = executableExists('   ', exists: (_) => false);

    expect(result, expected);
  });

  test('a path is valid when it exists', () {
    const expected = true;

    final result = executableExists(
      r'C:\custom\shell.exe',
      exists: (path) => path == r'C:\custom\shell.exe',
    );

    expect(result, expected);
  });

  test('a path is invalid when it does not exist', () {
    const expected = false;

    final result = executableExists(
      r'C:\missing\shell.exe',
      exists: (_) => false,
    );

    expect(result, expected);
  });
}

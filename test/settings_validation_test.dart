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

  test('clampFontSize passes a value already in range through unchanged', () {
    const expected = 16.0;

    final result = clampFontSize(16);

    expect(result, expected);
  });

  test('clampFontSize raises a value below the minimum to the minimum', () {
    const expected = minTerminalFontSize;

    final result = clampFontSize(2);

    expect(result, expected);
  });

  test('clampFontSize lowers a value above the maximum to the maximum', () {
    const expected = maxTerminalFontSize;

    final result = clampFontSize(50);

    expect(result, expected);
  });

  test('parseHistoryLines accepts a value in range', () {
    const expected = 20000;

    final result = parseHistoryLines('20000');

    expect(result, expected);
  });

  test('parseHistoryLines trims surrounding whitespace', () {
    const expected = 20000;

    final result = parseHistoryLines('  20000  ');

    expect(result, expected);
  });

  test('parseHistoryLines rejects a non-numeric value', () {
    const expected = null;

    final result = parseHistoryLines('not-a-number');

    expect(result, expected);
  });

  test('parseHistoryLines rejects a value below the minimum', () {
    const expected = null;

    final result = parseHistoryLines('${minHistoryLines - 1}');

    expect(result, expected);
  });

  test('parseHistoryLines rejects a value above the maximum', () {
    const expected = null;

    final result = parseHistoryLines('${maxHistoryLines + 1}');

    expect(result, expected);
  });

  test('parseHistoryLines accepts the boundary values', () {
    final expected = [minHistoryLines, maxHistoryLines];

    final result = [
      parseHistoryLines('$minHistoryLines'),
      parseHistoryLines('$maxHistoryLines'),
    ];

    expect(result, expected);
  });

  test('patternLinesFromText trims each line and drops blank ones', () {
    const expected = [r'^https://a/', r'b\.com'];

    final result = patternLinesFromText('  ^https://a/  \r\n\n   \nb\\.com\n');

    expect(result, expected);
  });

  test('patternLinesFromText of an empty string is an empty list', () {
    const expected = <String>[];

    final result = patternLinesFromText('');

    expect(result, expected);
  });

  test('firstPatternError is null when every line is a valid regex', () {
    const expected = null;

    final result = firstPatternError('^https://a/\n\n(b|c)\\.com');

    expect(result, expected);
  });

  test('firstPatternError names the line of the first invalid regex', () {
    const expected = 2;

    final result = firstPatternError('^https://ok/\n^https://(broken\n(also');

    expect(result?.line, expected);
  });

  test(
    'firstPatternError counts blank lines so the number matches the field',
    () {
      const expected = 3;

      final result = firstPatternError('^ok\n\n(broken');

      expect(result?.line, expected);
    },
  );

  test('firstPatternError carries a non-empty reason', () {
    const expected = true;

    final result = firstPatternError('(broken');

    expect(result?.reason.isNotEmpty, expected);
  });

  test('firstPatternError ignores blank lines', () {
    const expected = null;

    final result = firstPatternError('\n   \n');

    expect(result, expected);
  });
}

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
}

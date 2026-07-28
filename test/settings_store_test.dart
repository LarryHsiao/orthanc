import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/settings_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'orthanc_settings_store_test',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('reading a missing settings file returns the default settings', () {
    const expected = null;
    final file = settingsFile(supportDir: tempDir);

    final result = readSettings(file: file);

    expect(result.executablePath, expected);
  });

  test(
    'reading a missing settings file defaults to TerminalColorScheme.defaultScheme',
    () {
      const expected = TerminalColorScheme.defaultScheme;
      final file = settingsFile(supportDir: tempDir);

      final result = readSettings(file: file);

      expect(result.colorScheme, expected);
    },
  );

  test('writing then reading round-trips the executable path', () {
    const expected = r'C:\custom\shell.exe';
    final file = settingsFile(supportDir: tempDir);

    writeSettings(const Settings(executablePath: expected), file: file);
    final result = readSettings(file: file);

    expect(result.executablePath, expected);
  });

  test('writing then reading round-trips the color scheme', () {
    const expected = TerminalColorScheme.dracula;
    final file = settingsFile(supportDir: tempDir);

    writeSettings(const Settings(colorScheme: expected), file: file);
    final result = readSettings(file: file);

    expect(result.colorScheme, expected);
  });

  test('reading an unknown color scheme name returns the default scheme', () {
    const expected = TerminalColorScheme.defaultScheme;
    final file = settingsFile(supportDir: tempDir);
    file.createSync(recursive: true);
    file.writeAsStringSync('{"colorScheme": "notAScheme"}');

    final result = readSettings(file: file);

    expect(result.colorScheme, expected);
  });

  test('reading a corrupt settings file returns the default settings', () {
    const expected = null;
    final file = settingsFile(supportDir: tempDir);
    file.createSync(recursive: true);
    file.writeAsStringSync('{not valid json');

    final result = readSettings(file: file);

    expect(result.executablePath, expected);
  });

  test(
    'reading valid JSON with wrong-typed field returns the default settings',
    () {
      const expected = null;
      final file = settingsFile(supportDir: tempDir);
      file.createSync(recursive: true);
      file.writeAsStringSync('{"executablePath": 123}');

      final result = readSettings(file: file);

      expect(result.executablePath, expected);
    },
  );
}

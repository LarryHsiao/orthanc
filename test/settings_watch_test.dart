import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/settings_store.dart';
import 'package:orthanc/settings_watch.dart';

void main() {
  test('returns next when executablePath differs', () {
    const current = Settings(executablePath: 'a');
    const next = Settings(executablePath: 'b');

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(next));
  });

  test('returns next when colorScheme differs', () {
    const current = Settings(colorScheme: TerminalColorScheme.defaultScheme);
    const next = Settings(colorScheme: TerminalColorScheme.dracula);

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(next));
  });

  test('returns next when fontFamily differs', () {
    const current = Settings(fontFamily: TerminalFontFamily.defaultFamily);
    const next = Settings(fontFamily: TerminalFontFamily.menlo);

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(next));
  });

  test('returns next when fontSize differs', () {
    const current = Settings(fontSize: 12);
    const next = Settings(fontSize: 14);

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(next));
  });

  test('returns current unchanged when every field is identical', () {
    const current = Settings(
      executablePath: 'a',
      colorScheme: TerminalColorScheme.dracula,
      fontFamily: TerminalFontFamily.menlo,
      fontSize: 13,
    );
    const next = Settings(
      executablePath: 'a',
      colorScheme: TerminalColorScheme.dracula,
      fontFamily: TerminalFontFamily.menlo,
      fontSize: 13,
    );

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(current));
  });

  test('reloads settings after an external atomic-rename write', () async {
    const expected = TerminalColorScheme.dracula;
    final tempDir = Directory.systemTemp.createTempSync(
      'orthanc_settings_watch_integration_test',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final file = settingsFile(supportDir: tempDir);
    // Seeds the file directly rather than via writeSettings(): that helper
    // always renames from the same pid-based temp path, and two renames
    // through that identical path from this same process — one to seed,
    // one to trigger the watch below — land close enough together that
    // macOS FSEvents coalesces them and silently drops the second's modify
    // event. The write under test still goes through the real
    // writeSettings() atomic-rename path below, which is what this test
    // means to exercise.
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(settingsToJson(const Settings())));
    final settings = ValueNotifier(readSettings(file: file));

    watchSettingsFile(file: file, settings: settings);
    writeSettings(const Settings(colorScheme: expected), file: file);

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (settings.value.colorScheme != expected &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    expect(settings.value.colorScheme, expected);
  });
}

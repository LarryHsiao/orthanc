import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';

void main() {
  test('round-trips executablePath through json', () {
    const expected = r'C:\custom\shell.exe';
    final settings = Settings(executablePath: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.executablePath, expected);
  });

  test('a missing executablePath field decodes to null', () {
    const expected = null;

    final result = settingsFromJson(const {});

    expect(result.executablePath, expected);
  });

  test('a blank executablePath in json decodes to null', () {
    const expected = null;

    final result = settingsFromJson(const {'executablePath': '   '});

    expect(result.executablePath, expected);
  });

  test('normalizeExecutablePath trims a real path', () {
    const expected = r'C:\custom\shell.exe';

    final result = normalizeExecutablePath('  C:\\custom\\shell.exe  ');

    expect(result, expected);
  });

  test('normalizeExecutablePath treats a blank string as null', () {
    const expected = null;

    final result = normalizeExecutablePath('   ');

    expect(result, expected);
  });

  test('normalizeExecutablePath passes null through', () {
    const expected = null;

    final result = normalizeExecutablePath(null);

    expect(result, expected);
  });

  test('round-trips fontFamily through json', () {
    const expected = TerminalFontFamily.jetBrainsMono;
    final settings = Settings(fontFamily: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.fontFamily, expected);
  });

  test('a missing fontFamily field decodes to defaultFamily', () {
    const expected = TerminalFontFamily.defaultFamily;

    final result = settingsFromJson(const {});

    expect(result.fontFamily, expected);
  });

  test('an unrecognized fontFamily name decodes to defaultFamily', () {
    const expected = TerminalFontFamily.defaultFamily;

    final result = settingsFromJson(const {'fontFamily': 'not-a-real-font'});

    expect(result.fontFamily, expected);
  });

  test('round-trips fontSize through json', () {
    const expected = 18.0;
    final settings = Settings(fontSize: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.fontSize, expected);
  });

  test('a missing fontSize field decodes to null', () {
    const expected = null;

    final result = settingsFromJson(const {});

    expect(result.fontSize, expected);
  });

  test('an integer fontSize in json decodes to a double', () {
    const expected = 16.0;

    final result = settingsFromJson(const {'fontSize': 16});

    expect(result.fontSize, expected);
  });

  test('round-trips startQuakeAtLogin through json', () {
    const expected = true;
    final settings = Settings(startQuakeAtLogin: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.startQuakeAtLogin, expected);
  });

  test('a missing startQuakeAtLogin field decodes to false', () {
    const expected = false;

    final result = settingsFromJson(const {});

    expect(result.startQuakeAtLogin, expected);
  });
}

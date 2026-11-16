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

  test('round-trips historyLines through json', () {
    const expected = 50000;
    final settings = Settings(historyLines: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.historyLines, expected);
  });

  test('a missing historyLines field decodes to defaultHistoryLines', () {
    const expected = defaultHistoryLines;

    final result = settingsFromJson(const {});

    expect(result.historyLines, expected);
  });

  test('link preview is off by default', () {
    const expected = false;

    final result = settingsFromJson(const {});

    expect(result.linkPreviewEnabled, expected);
  });

  test('round-trips linkPreviewEnabled through json', () {
    const expected = true;
    final settings = Settings(linkPreviewEnabled: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.linkPreviewEnabled, expected);
  });

  test('a missing linkPreviewNever field decodes to the seeded list', () {
    const expected = defaultLinkPreviewNever;

    final result = settingsFromJson(const {});

    expect(result.linkPreviewNever, expected);
  });

  test('an explicitly empty linkPreviewNever stays empty, not re-seeded', () {
    const expected = <String>[];

    final result = settingsFromJson(const {'linkPreviewNever': <String>[]});

    expect(result.linkPreviewNever, expected);
  });

  test('round-trips linkPreviewNever through json', () {
    const expected = [r'^https://a\.example/', r'\.corp/'];
    final settings = Settings(linkPreviewNever: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.linkPreviewNever, expected);
  });

  test('a missing linkPreviewOnly field decodes to an empty list', () {
    const expected = <String>[];

    final result = settingsFromJson(const {});

    expect(result.linkPreviewOnly, expected);
  });

  test('round-trips linkPreviewOnly through json', () {
    const expected = [r'^https://github\.com/'];
    final settings = Settings(linkPreviewOnly: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.linkPreviewOnly, expected);
  });

  test('a non-list linkPreviewNever decodes to the seeded list', () {
    const expected = defaultLinkPreviewNever;

    final result = settingsFromJson(const {'linkPreviewNever': 'oops'});

    expect(result.linkPreviewNever, expected);
  });

  test('non-string entries in a link preview list are dropped', () {
    const expected = [r'^https://ok/'];

    final result = settingsFromJson(const {
      'linkPreviewOnly': [r'^https://ok/', 7, null],
    });

    expect(result.linkPreviewOnly, expected);
  });
}

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
}

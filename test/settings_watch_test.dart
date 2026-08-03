import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
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
}

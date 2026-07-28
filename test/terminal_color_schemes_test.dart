import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_color_schemes.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('defaultScheme maps to xterm\'s own default theme', () {
    final expected = TerminalThemes.defaultTheme;

    final result = terminalThemeFor(TerminalColorScheme.defaultScheme);

    expect(result.background, expected.background);
    expect(result.foreground, expected.foreground);
  });

  test('whiteOnBlack maps to xterm\'s own white-on-black theme', () {
    final expected = TerminalThemes.whiteOnBlack;

    final result = terminalThemeFor(TerminalColorScheme.whiteOnBlack);

    expect(result.background, expected.background);
    expect(result.foreground, expected.foreground);
  });

  test('every scheme resolves to a theme with a distinct background', () {
    final backgrounds = TerminalColorScheme.values
        .map((scheme) => terminalThemeFor(scheme).background)
        .toSet();

    expect(backgrounds.length, TerminalColorScheme.values.length);
  });

  test('every scheme has a non-empty display label', () {
    for (final scheme in TerminalColorScheme.values) {
      expect(terminalColorSchemeLabel(scheme), isNotEmpty);
    }
  });

  test('labels name each scheme', () {
    const expected = {
      TerminalColorScheme.defaultScheme: 'Default',
      TerminalColorScheme.whiteOnBlack: 'White on Black',
      TerminalColorScheme.dracula: 'Dracula',
      TerminalColorScheme.solarizedDark: 'Solarized Dark',
      TerminalColorScheme.monokai: 'Monokai',
      TerminalColorScheme.oneDark: 'One Dark',
    };

    for (final entry in expected.entries) {
      expect(terminalColorSchemeLabel(entry.key), entry.value);
    }
  });
}

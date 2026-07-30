import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_font_families.dart';

void main() {
  test('defaultFamily resolves to the default font family constant', () {
    const expected = defaultTerminalFontFamily;

    final result = terminalFontFamilyName(TerminalFontFamily.defaultFamily);

    expect(result, expected);
  });

  test('every family resolves to a non-empty name', () {
    for (final family in TerminalFontFamily.values) {
      expect(terminalFontFamilyName(family), isNotEmpty);
    }
  });

  test('every family has a non-empty display label', () {
    for (final family in TerminalFontFamily.values) {
      expect(terminalFontFamilyLabel(family), isNotEmpty);
    }
  });

  test('labels name each family', () {
    const expected = {
      TerminalFontFamily.defaultFamily: 'Default',
      TerminalFontFamily.hackNerdFontMono: 'Hack Nerd Font Mono',
      TerminalFontFamily.menlo: 'Menlo',
      TerminalFontFamily.monaco: 'Monaco',
      TerminalFontFamily.consolas: 'Consolas',
      TerminalFontFamily.jetBrainsMono: 'JetBrains Mono',
      TerminalFontFamily.firaCode: 'Fira Code',
      TerminalFontFamily.cascadiaCode: 'Cascadia Code',
      TerminalFontFamily.courierNew: 'Courier New',
    };

    for (final entry in expected.entries) {
      expect(terminalFontFamilyLabel(entry.key), entry.value);
    }
  });

  test(
    'names match the literal font-family string for every non-default family',
    () {
      const expected = {
        TerminalFontFamily.hackNerdFontMono: 'Hack Nerd Font Mono',
        TerminalFontFamily.menlo: 'Menlo',
        TerminalFontFamily.monaco: 'Monaco',
        TerminalFontFamily.consolas: 'Consolas',
        TerminalFontFamily.jetBrainsMono: 'JetBrains Mono',
        TerminalFontFamily.firaCode: 'Fira Code',
        TerminalFontFamily.cascadiaCode: 'Cascadia Code',
        TerminalFontFamily.courierNew: 'Courier New',
      };

      for (final entry in expected.entries) {
        expect(terminalFontFamilyName(entry.key), entry.value);
      }
    },
  );
}

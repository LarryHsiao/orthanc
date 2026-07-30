import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_color_schemes.dart';
import 'package:orthanc/terminal_font_families.dart';
import 'package:orthanc/terminal_preview.dart';
import 'package:xterm/xterm.dart';

void main() {
  test(
    'sample terminal shows a prompt, colored listing, and an error line',
    () {
      const expected = [
        'orthanc:~ \$ ls -la',
        'Documents  Downloads  Projects  notes.txt',
        'zsh: command not found: fzf',
        '‣ main ✗',
      ];

      final terminal = buildPreviewTerminal();

      final lines = List.generate(
        expected.length,
        (i) => terminal.buffer.lines[i].getText(),
      );
      expect(lines, expected);
    },
  );

  testWidgets('renders a read-only TerminalView themed for the given scheme', (
    tester,
  ) async {
    const scheme = TerminalColorScheme.nord;
    final expected = terminalThemeFor(scheme);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TerminalPreview(
          scheme: scheme,
          fontFamily: defaultTerminalFontFamily,
          fontSize: defaultTerminalFontSize,
        ),
      ),
    );

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.theme.background, expected.background);
    expect(view.readOnly, isTrue);
  });

  testWidgets('renders with the given font family and size', (tester) async {
    const scheme = TerminalColorScheme.defaultScheme;
    const expectedFamily = 'JetBrains Mono';
    const expectedSize = 18.0;

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TerminalPreview(
          scheme: scheme,
          fontFamily: expectedFamily,
          fontSize: expectedSize,
        ),
      ),
    );

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.textStyle.fontFamily, expectedFamily);
    expect(view.textStyle.fontSize, expectedSize);
  });

  testWidgets('renders with the standard font family and size constants', (
    tester,
  ) async {
    const scheme = TerminalColorScheme.defaultScheme;

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TerminalPreview(
          scheme: scheme,
          fontFamily: defaultTerminalFontFamily,
          fontSize: defaultTerminalFontSize,
        ),
      ),
    );

    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    expect(view.textStyle.fontFamily, defaultTerminalFontFamily);
    expect(view.textStyle.fontSize, defaultTerminalFontSize);
  });
}

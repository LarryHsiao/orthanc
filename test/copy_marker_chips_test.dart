import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/copy_marker_chips.dart';
import 'package:xterm/xterm.dart';

void main() {
  const idle = Color(0xFFF9A825);
  const hover = Color(0xFFFFC947);
  const done = Color(0xFFA6E3A1);

  Future<Terminal> pump(
    WidgetTester tester, {
    required String output,
    ValueNotifier<String?>? hovered,
    ValueNotifier<String?>? copied,
  }) async {
    final terminal = Terminal()..write(output);
    final key = GlobalKey<TerminalViewState>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              TerminalView(terminal, key: key, scrollController: scroll),
              Positioned.fill(
                child: CopyMarkerChips(
                  terminal: terminal,
                  scrollController: scroll,
                  geometry: () => terminalGeometry(key),
                  textStyle: const TextStyle(fontSize: 14),
                  background: idle,
                  hoverBackground: hover,
                  copiedBackground: done,
                  foreground: Colors.black,
                  hovered: hovered ?? ValueNotifier<String?>(null),
                  copied: copied ?? ValueNotifier<String?>(null),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    return terminal;
  }

  Color? fillOf(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find.byKey(CopyMarkerChips.chipKey).first,
    );
    return (box.decoration as BoxDecoration).color;
  }

  testWidgets('a visible marker draws one chip labelled Copy and the name', (
    tester,
  ) async {
    await pump(tester, output: 'hi\r\n⧉ copy:block-1');

    expect(find.byKey(CopyMarkerChips.chipKey), findsOneWidget);
    expect(find.text('⧉ Copy block-1'), findsOneWidget);
  });

  testWidgets('output with no marker draws no chip', (tester) async {
    await pump(tester, output: 'plain output');

    expect(find.byKey(CopyMarkerChips.chipKey), findsNothing);
  });

  testWidgets('a marker arriving later draws its chip', (tester) async {
    final terminal = await pump(tester, output: 'plain');

    terminal.write('\r\n⧉ copy:late.sh');
    await tester.pump();

    expect(find.text('⧉ Copy late.sh'), findsOneWidget);
  });

  testWidgets('the chip is idle-coloured until its block is hovered', (
    tester,
  ) async {
    final hovered = ValueNotifier<String?>(null);
    await pump(tester, output: '⧉ copy:block-1', hovered: hovered);
    final idleFill = fillOf(tester);

    hovered.value = 'block-1';
    await tester.pump();
    final hoverFill = fillOf(tester);

    expect([idleFill, hoverFill], [idle, hover]);
  });

  testWidgets('the chip does not take pointer events', (tester) async {
    await pump(tester, output: '⧉ copy:block-1');

    final ignoring = tester.widget<IgnorePointer>(
      find
          .descendant(
            of: find.byType(CopyMarkerChips),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );

    expect(ignoring.ignoring, isTrue);
  });

  testWidgets('a copied block shows Copied in the copied colour', (
    tester,
  ) async {
    final copied = ValueNotifier<String?>(null);
    await pump(tester, output: '⧉ copy:block-1', copied: copied);

    copied.value = 'block-1';
    await tester.pump();

    expect(
      [find.textContaining('✓ Copied').evaluate().length, fillOf(tester)],
      [1, done],
    );
  });

  testWidgets('a copied label fills the marker cells and no more', (
    tester,
  ) async {
    final copied = ValueNotifier<String?>('block-1');
    await pump(tester, output: '⧉ copy:block-1', copied: copied);
    // 14 marker cells: the 8-character label, then padding to the same width.
    const expected = '✓ Copied      ';

    final label = tester.widget<Text>(
      find.descendant(
        of: find.byKey(CopyMarkerChips.chipKey),
        matching: find.byType(Text),
      ),
    );

    expect(label.data, expected);
  });
}

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/copy_marker.dart';
import 'package:orthanc/copy_marker_chips.dart';
import 'package:orthanc/pane_view.dart';
import 'package:orthanc/session.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_color_schemes.dart';
import 'package:orthanc/terminal_font_families.dart';
import 'package:path/path.dart' as p;

void main() {
  final theme = terminalThemeFor(TerminalColorScheme.dracula);
  const blockName = 'chip-test-block.sh';
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<Session> pumpPane(WidgetTester tester, String output) async {
    final session = Session(id: 'a', executable: 'cmd.exe');
    addTearDown(session.dispose);
    session.terminal.write(output);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneView(
            session: session,
            focused: true,
            onFocus: () {},
            onKeyEvent: (node, event) => KeyEventResult.ignored,
            canCollapse: false,
            collapsed: false,
            theme: theme,
            fontFamily: terminalFontFamilyName(
              TerminalFontFamily.defaultFamily,
            ),
            fontSize: defaultTerminalFontSize,
            onToggleCollapse: () {},
            onExpand: () {},
            canDrag: false,
            onDragStart: (_) {},
            onDragUpdate: (_, _) {},
            onDragEnd: (_) {},
            isDropTarget: false,
            isBeingDragged: false,
            dropSide: null,
            isFileDropTarget: false,
          ),
        ),
      ),
    );
    await tester.pump();
    return session;
  }

  testWidgets('a marker in the pane draws a chip', (tester) async {
    await pumpPane(tester, '⧉ copy:$blockName');

    expect(find.byKey(CopyMarkerChips.chipKey), findsOneWidget);
  });

  testWidgets('clicking the chip puts the block file on the clipboard', (
    tester,
  ) async {
    const expected = 'echo chip\n';
    final dir = Directory(copyBlockDirectory)..createSync(recursive: true);
    final file = File(p.join(dir.path, blockName))..writeAsStringSync(expected);
    addTearDown(file.deleteSync);
    await pumpPane(tester, '⧉ copy:$blockName');

    await tester.tapAt(tester.getCenter(find.byKey(CopyMarkerChips.chipKey)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(clipboardText, expected);
  });

  testWidgets('hovering the chip brightens it', (tester) async {
    await pumpPane(tester, '⧉ copy:$blockName');
    Color? fill() =>
        (tester
                    .widget<DecoratedBox>(find.byKey(CopyMarkerChips.chipKey))
                    .decoration
                as BoxDecoration)
            .color;
    final idle = fill();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.byKey(CopyMarkerChips.chipKey)));
    await tester.pump();
    final hover = fill();

    expect(hover, isNot(idle));
  });

  testWidgets('a click flashes Copied, then the chip reverts', (tester) async {
    final dir = Directory(copyBlockDirectory)..createSync(recursive: true);
    final file = File(p.join(dir.path, blockName))..writeAsStringSync('x');
    addTearDown(file.deleteSync);
    await pumpPane(tester, '⧉ copy:$blockName');

    await tester.tapAt(tester.getCenter(find.byKey(CopyMarkerChips.chipKey)));
    await tester.pump(const Duration(milliseconds: 400));
    final during = find.textContaining('✓ Copied').evaluate().length;
    await tester.pump(const Duration(seconds: 2));
    final after = find.textContaining('✓ Copied').evaluate().length;

    expect([during, after], [1, 0]);
  });

  testWidgets('a click on a missing block flashes nothing', (tester) async {
    await pumpPane(tester, '⧉ copy:absent-block.sh');

    await tester.tapAt(tester.getCenter(find.byKey(CopyMarkerChips.chipKey)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('✓ Copied'), findsNothing);
  });

  testWidgets('the chip dims again once the pointer leaves', (tester) async {
    await pumpPane(tester, '⧉ copy:$blockName');
    Color? fill() =>
        (tester
                    .widget<DecoratedBox>(find.byKey(CopyMarkerChips.chipKey))
                    .decoration
                as BoxDecoration)
            .color;
    final idle = fill();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(CopyMarkerChips.chipKey)));
    await tester.pump();

    await mouse.moveTo(const Offset(2000, 2000));
    await tester.pump();

    expect(fill(), idle);
  });
}

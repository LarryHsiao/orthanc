import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/layout_node.dart';
import 'package:orthanc/pane_view.dart';
import 'package:orthanc/sessions.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/split_view.dart';
import 'package:orthanc/terminal_color_schemes.dart';
import 'package:orthanc/terminal_font_families.dart';

void main() {
  Future<void> pumpSplitView(
    WidgetTester tester, {
    required LayoutNode node,
    required String focusedId,
    required bool highlightFocus,
    required Sessions sessions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitView(
            node: node,
            sessions: sessions,
            focusedId: focusedId,
            highlightFocus: highlightFocus,
            collapsedIds: const {},
            collapsibleIds: const {},
            theme: terminalThemeFor(TerminalColorScheme.dracula),
            fontFamily: terminalFontFamilyName(
              TerminalFontFamily.defaultFamily,
            ),
            fontSize: defaultTerminalFontSize,
            onFocus: (_) {},
            onResize: (_, _, _) {},
            onToggleCollapse: (_) {},
            onKeyEvent: (node, event) => KeyEventResult.ignored,
          ),
        ),
      ),
    );
  }

  Sessions newSessions() {
    final sessions = Sessions(settings: ValueNotifier(const Settings()));
    addTearDown(sessions.disposeAll);
    return sessions;
  }

  testWidgets('a window holding one pane marks nothing', (tester) async {
    final sessions = newSessions();
    final only = sessions.spawn();

    await pumpSplitView(
      tester,
      node: PaneNode(only.id),
      focusedId: only.id,
      highlightFocus: false,
      sessions: sessions,
    );

    expect(find.byKey(PaneView.focusBorderKey), findsNothing);
  });

  testWidgets('a split window marks exactly the focused pane', (tester) async {
    final sessions = newSessions();
    final first = sessions.spawn();
    final second = sessions.spawn();

    await pumpSplitView(
      tester,
      node: SplitNode(
        axis: SplitAxis.row,
        children: [PaneNode(first.id), PaneNode(second.id)],
        ratios: const [0.5, 0.5],
      ),
      focusedId: second.id,
      highlightFocus: true,
      sessions: sessions,
    );

    expect(find.byKey(PaneView.focusBorderKey), findsOneWidget);
  });
}

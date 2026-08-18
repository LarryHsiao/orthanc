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
  // A known box to lay the tree out in, pinned to the top-left so a child's
  // bottom edge can be compared against [boundsHeight] directly.
  const boundsWidth = 400.0;
  const boundsHeight = 300.0;

  Future<void> pumpSplitView(
    WidgetTester tester, {
    required LayoutNode node,
    required String focusedId,
    required bool highlightFocus,
    required Sessions sessions,
    Set<String> collapsedIds = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: boundsWidth,
              height: boundsHeight,
              child: SplitView(
                node: node,
                sessions: sessions,
                focusedId: focusedId,
                highlightFocus: highlightFocus,
                collapsedIds: collapsedIds,
                collapsibleIds: const {},
                theme: terminalThemeFor(TerminalColorScheme.dracula),
                fontFamily: terminalFontFamilyName(
                  TerminalFontFamily.defaultFamily,
                ),
                fontSize: defaultTerminalFontSize,
                onFocus: (_) {},
                onResize: (_, _, _) {},
                onToggleCollapse: (_) {},
                onExpand: (_) {},
                onKeyEvent: (node, event) => KeyEventResult.ignored,
                canDrag: false,
                onDragStart: (_) {},
                onDragUpdate: (_, _) {},
                onDragEnd: (_) {},
                dragSourceId: null,
                dragHoverId: null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Where the last child of the laid-out tree ends, in the bounds' own
  /// coordinates — [boundsHeight] exactly when the tree fills its parent.
  double bottomOfLastPane(WidgetTester tester) =>
      tester.getRect(find.byType(PaneView).last).bottom;

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

  testWidgets('a two-row column with one pane collapsed reaches its parent\'s '
      'bottom edge', (tester) async {
    const expected = boundsHeight;
    final sessions = newSessions();
    final top = sessions.spawn();
    final bottom = sessions.spawn();

    await pumpSplitView(
      tester,
      node: SplitNode(
        axis: SplitAxis.column,
        children: [PaneNode(top.id), PaneNode(bottom.id)],
        ratios: const [0.5, 0.5],
      ),
      focusedId: bottom.id,
      highlightFocus: true,
      sessions: sessions,
      collapsedIds: {top.id},
    );

    expect(bottomOfLastPane(tester), expected);
  });

  testWidgets('a three-row column with one pane collapsed reaches its '
      'parent\'s bottom edge', (tester) async {
    const expected = boundsHeight;
    final sessions = newSessions();
    final top = sessions.spawn();
    final middle = sessions.spawn();
    final bottom = sessions.spawn();

    await pumpSplitView(
      tester,
      node: SplitNode(
        axis: SplitAxis.column,
        children: [PaneNode(top.id), PaneNode(middle.id), PaneNode(bottom.id)],
        ratios: const [1 / 3, 1 / 3, 1 / 3],
      ),
      focusedId: bottom.id,
      highlightFocus: true,
      sessions: sessions,
      collapsedIds: {middle.id},
    );

    expect(bottomOfLastPane(tester), expected);
  });

  testWidgets('a column with nothing collapsed still reaches its parent\'s '
      'bottom edge, dividers and all', (tester) async {
    const expected = boundsHeight;
    final sessions = newSessions();
    final top = sessions.spawn();
    final bottom = sessions.spawn();

    await pumpSplitView(
      tester,
      node: SplitNode(
        axis: SplitAxis.column,
        children: [PaneNode(top.id), PaneNode(bottom.id)],
        ratios: const [0.5, 0.5],
      ),
      focusedId: bottom.id,
      highlightFocus: true,
      sessions: sessions,
    );

    expect(bottomOfLastPane(tester), expected);
  });
}

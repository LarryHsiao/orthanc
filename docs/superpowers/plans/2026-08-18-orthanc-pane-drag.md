# Pane Drag (Swap) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a pane be picked up by a grip on its bar and dropped onto
another pane to trade places with it — same tree shape, same ratios,
only the two sessions' positions exchange. Layer 1 of two; move-and-
re-split is explicitly out of scope for this plan.

**Architecture:** `Workspace` gains `swap(sourceId, targetId)`, which
relabels two `PaneNode` leaves in place (no shape, axis, or ratio change)
and reuses the existing `_collectCollapsible`/`_releaseEmptiedColumns`
pair to drop any `collapsedIds` entry the swap leaves illegal. `PaneBar`
gains a `canDrag` flag and a small grip glyph carrying its own pan
gesture, reported up as the pane's own session id plus the pointer's
global position. `PaneView` and `SplitView` thread `canDrag` and the
three drag callbacks straight through, the same shape `canCollapse`/
`onToggleCollapse` already take. `WorkspaceView` owns the drag state
(`_dragSourceId`, `_dragHoverId`), converts the pointer's global position
into the same fractional space `Workspace.paneRects()` already speaks
via a `GlobalKey`-measured bounding box, and calls `workspace.swap(...)`
on release.

**Tech Stack:** Flutter/Dart, `flutter_test` (widget tests exist in this
codebase for `PaneBar`/`PaneView`/`SplitView` — see Global Constraints).

## Global Constraints

- Match existing test style exactly: `group`/`test`, a named `expected`
  (or `expectedX`) constant declared before the call, then one assertion
  comparing against it — see `test/workspace_test.dart` for the pattern.
- Every `Workspace` operation stays immutable — return a new `Workspace`,
  never mutate `this`.
- `swap` must thread `collapsedIds` through the same cleanup `close()`
  already performs (`_collectCollapsible` → intersect →
  `_releaseEmptiedColumns`) — do not hand-roll a second version of that
  logic.
- The grip must never be reachable from the terminal body — only from
  `PaneBar`. Do not add any gesture handling to the `TerminalView`/
  `ClipRect`/`MouseRegion` region in `pane_view.dart`.
- These files need **no** changes — if you want to touch them, stop:
  `lib/layout_node.dart`, `lib/sessions.dart`, `lib/session.dart`,
  `lib/split_shortcuts.dart`.

---

### Task 1: `Workspace.swap`

**Files:**
- Modify: `lib/workspace.dart`
- Test: `test/workspace_test.dart`

**Interfaces:**
- Produces: `Workspace.swap(String sourceId, String targetId) -> Workspace`.

- [ ] **Step 1: Write the failing tests**

Add a new group at the end of `test/workspace_test.dart`, just before the
file's closing `}` (after `group('Workspace.collapsibleIds', ...)`):

```dart
  group('Workspace.swap', () {
    test('a slot keeps its own ratio after a swap changes which session '
        'fills it', () {
      final expected = [0.7, 0.3];

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');
      final resized = workspace.resizeSplit(
        split: workspace.root,
        dividerIndex: 0,
        delta: 0.2,
      );
      final swapped = resized.swap('a', 'b');

      expect((swapped.root as SplitNode).ratios, expected);
    });

    test('trades which session each slot shows', () {
      final expected = ['b', 'a'];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .swap('a', 'b');

      expect(workspace.sessionIds, expected);
    });

    test('is a no-op when both ids are the same', () {
      final expected = ['a', 'b'];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .swap('a', 'a');

      expect(workspace.sessionIds, expected);
    });

    test('reaches across the tree, swapping panes in different branches', () {
      final expected = ['c', 'b', 'a'];

      // a | (b over c) — swap the row's own first child with the deeper 'c'.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .swap('a', 'c');

      expect(workspace.sessionIds, expected);
    });

    test('focuses the session it swapped, wherever it lands', () {
      const expected = 'a';

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .focus('b')
          .swap('a', 'b');

      expect(workspace.focusedId, expected);
    });

    test('drops a collapse entry the swap leaves illegal', () {
      final expected = <String>{};

      // column[row[a, c], b], with 'b' collapsed. Swapping 'b' for 'c'
      // moves 'b' into the row, where collapse is never legal — the
      // stale entry must not survive.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .swap('b', 'c');

      expect(workspace.collapsedIds, expected);
    });

    test('leaves an unrelated pane\'s collapse entry alone', () {
      final expected = {'d'};

      // (a over b) | (c over d), with 'd' collapsed. Swapping 'a' and 'b'
      // in the left column must not touch the right column's own entry —
      // a swap never changes tree shape, so 'd's own collapsibility can't
      // move regardless of what 'a' and 'b' do.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .split(axis: SplitAxis.column, newSessionId: 'd')
          .toggleCollapse('d')
          .swap('a', 'b');

      expect(workspace.collapsedIds, expected);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — `Workspace.swap` is undefined.

- [ ] **Step 3: Implement `swap`**

In `lib/workspace.dart`, add just after `_releaseEmptiedColumns` (which
ends the `close()`-related group, right before `paneRects()`):

```dart
  /// Exchanges the sessions at [sourceId] and [targetId]'s positions in
  /// the tree. The two [PaneNode] leaves trade which session id they
  /// hold; nothing about the tree's shape, axes, or ratios changes — a
  /// slot's size belongs to the slot, not to whichever session currently
  /// fills it. A no-op when [sourceId] and [targetId] are the same id.
  /// Focuses [sourceId] wherever it lands, mirroring [toggleCollapse] and
  /// [split]'s own convention of focusing the pane the operation acted
  /// on.
  ///
  /// Runs the same collapse cleanup [close] already performs: any
  /// [collapsedIds] entry the swap leaves illegal (its pane's new parent
  /// no longer a qualifying column) is dropped, and a column the swap
  /// would leave holding nothing but bars is released back to even
  /// shares. Neither id is ever added to [collapsedIds] by a swap —
  /// only entries already present can be dropped.
  Workspace swap(String sourceId, String targetId) {
    if (sourceId == targetId) return this;

    final swapped = _swapped(root, sourceId, targetId);

    final collapsibleAfter = <String>{};
    _collectCollapsible(swapped, collapsibleAfter);
    final kept = collapsedIds.intersection(collapsibleAfter);
    _releaseEmptiedColumns(swapped, kept);

    return Workspace(root: swapped, focusedId: sourceId, collapsedIds: kept);
  }

  static LayoutNode _swapped(LayoutNode node, String a, String b) {
    if (node is PaneNode) {
      if (node.sessionId == a) return PaneNode(b);
      if (node.sessionId == b) return PaneNode(a);
      return node;
    }
    final split = node as SplitNode;
    return SplitNode(
      axis: split.axis,
      children: [for (final child in split.children) _swapped(child, a, b)],
      ratios: split.ratios,
    );
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — all new and existing tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/workspace.dart test/workspace_test.dart
git commit -m "Add Workspace.swap for exchanging two panes' sessions"
```

---

### Task 2: `PaneBar`'s drag grip

**Files:**
- Modify: `lib/pane_bar.dart`
- Test: `test/pane_bar_test.dart`

**Interfaces:**
- Produces: `PaneBar.canDrag` (`bool`), `PaneBar.onDragStart` (`void
  Function(String id)`), `PaneBar.onDragUpdate` (`void Function(String
  id, Offset globalPosition)`), `PaneBar.onDragEnd` (`void Function(String
  id)`).

This task stands alone — `PaneBar` is only ever *constructed* by
`PaneView`, which this task does not touch, so `flutter test
test/pane_bar_test.dart` compiles and runs against `pane_bar.dart` alone
without needing `pane_view.dart` updated yet. `PaneView`'s own call site
is fixed in Task 3.

- [ ] **Step 1: Write the failing tests**

In `test/pane_bar_test.dart`, add `canDrag`, `onDragStart`,
`onDragUpdate`, `onDragEnd` parameters to `pumpPaneBar` (near the top of
`main()`):

```dart
  Future<Session> pumpPaneBar(
    WidgetTester tester, {
    bool focused = true,
    Color accent = lightAccent,
    Color attentionAccent = lightAttentionAccent,
    bool canCollapse = false,
    bool collapsed = false,
    bool canDrag = false,
    void Function(String id)? onDragStart,
    void Function(String id, Offset globalPosition)? onDragUpdate,
    void Function(String id)? onDragEnd,
  }) async {
    final session = Session(id: 'a', executable: 'cmd.exe');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneBar(
            session: session,
            focused: focused,
            accent: accent,
            attentionAccent: attentionAccent,
            canCollapse: canCollapse,
            collapsed: collapsed,
            canDrag: canDrag,
            onDragStart: onDragStart ?? (_) {},
            onDragUpdate: onDragUpdate ?? (_, _) {},
            onDragEnd: onDragEnd ?? (_) {},
          ),
        ),
      ),
    );
    return session;
  }
```

Add these tests after the existing rename-related tests, before the
file's closing `}`:

```dart
  testWidgets('the grip is absent when the pane cannot be dragged', (
    tester,
  ) async {
    await pumpPaneBar(tester, canDrag: false);

    expect(find.byKey(PaneBar.gripKey), findsNothing);
  });

  testWidgets('dragging the grip reports this pane\'s own session id', (
    tester,
  ) async {
    const expected = 'a';
    String? started;
    String? ended;

    await pumpPaneBar(
      tester,
      canDrag: true,
      onDragStart: (id) => started = id,
      onDragEnd: (id) => ended = id,
    );
    await tester.drag(find.byKey(PaneBar.gripKey), const Offset(40, 0));

    expect(started, expected);
    expect(ended, expected);
  });

  testWidgets('dragging the grip reports the pointer\'s position along the '
      'way', (tester) async {
    final updates = <Offset>[];

    await pumpPaneBar(
      tester,
      canDrag: true,
      onDragUpdate: (id, position) => updates.add(position),
    );
    await tester.drag(find.byKey(PaneBar.gripKey), const Offset(40, 0));

    expect(updates, isNotEmpty);
  });

  testWidgets('right-click rename still works alongside a draggable grip', (
    tester,
  ) async {
    await pumpPaneBar(tester, canDrag: true);

    await rightClickPaneBar(tester);

    expect(find.byType(TextField), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/pane_bar_test.dart`
Expected: FAIL — `PaneBar.canDrag`, `onDragStart`, `onDragUpdate`,
`onDragEnd`, and `PaneBar.gripKey` are all undefined.

- [ ] **Step 3: Implement the grip**

In `lib/pane_bar.dart`, add to the `PaneBar` constructor and fields
(after `collapsed`, inside the existing constructor argument list and
field declarations at lines 22–51):

```dart
    required this.canDrag,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
```

```dart
  static const gripKey = Key('pane-drag-grip');

  final bool canDrag;

  /// Fired once, when a drag on the grip begins.
  final void Function(String id) onDragStart;

  /// Fired on every pointer move during a drag, with the pointer's
  /// current *global* position — the caller (ultimately [WorkspaceView])
  /// is what knows how to turn that into a pane underneath it.
  final void Function(String id, Offset globalPosition) onDragUpdate;

  /// Fired once, when the drag ends — by release or cancellation alike.
  final void Function(String id) onDragEnd;
```

Update `build`'s `Row` (current lines 95–101) to add the grip ahead of
the title:

```dart
            child: Row(
              children: [
                if (widget.canDrag) _grip(scheme),
                Expanded(child: _editing ? _editField(ink) : _title(ink)),
                if (widget.canCollapse)
                  _collapseIcon(emphasized ? ink : scheme.onSurfaceVariant),
              ],
            ),
```

Add a new method near `_collapseIcon`:

```dart
  Widget _grip(ColorScheme scheme) {
    return GestureDetector(
      key: PaneBar.gripKey,
      onPanStart: (_) => widget.onDragStart(widget.session.id),
      onPanUpdate: (details) =>
          widget.onDragUpdate(widget.session.id, details.globalPosition),
      onPanEnd: (_) => widget.onDragEnd(widget.session.id),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Text(
            '⠿',
            style: TextStyle(
              fontSize: 12,
              color: widget.focused
                  ? _inkOn(widget.accent)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
```

`_grip` takes `scheme` as a parameter rather than a second
`Theme.of(context)` lookup, since `_PaneBarState.build` already captures
it at its own top — update the `Row` shown above accordingly:
`if (widget.canDrag) _grip(scheme),`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/pane_bar_test.dart`
Expected: PASS — all new and existing tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/pane_bar.dart test/pane_bar_test.dart
git commit -m "Add a drag grip to PaneBar, reporting its own session id"
```

---

### Task 3: `PaneView`, `SplitView`, `WorkspaceView` — wired end to end

**Why one task:** the same reasoning as every prior feature's final
wiring task — `PaneView` requires arguments only `SplitView` can supply,
`SplitView` requires arguments only `WorkspaceView` can supply. None of
the three compiles against the others' *old* shape until all three are
updated together.

**Files:**
- Modify: `lib/pane_view.dart`
- Modify: `lib/split_view.dart`
- Modify: `lib/workspace_view.dart`
- Test: `test/pane_view_test.dart`

**Interfaces:**
- Consumes: `Workspace.swap` (Task 1), `PaneBar.canDrag`/`onDragStart`/
  `onDragUpdate`/`onDragEnd` (Task 2).
- Produces: the fully wired drag-to-swap behavior — nothing later
  depends on this task.

`SplitView` and `WorkspaceView` have no widget-test harness call sites
that isolate them from each other in this codebase (see
`test/split_view_test.dart`'s `pumpSplitView` helper, which already
takes every `SplitView` parameter) — the gesture-arena proof below lives
in `test/pane_view_test.dart`, and `split_view_test.dart`'s own
`pumpSplitView` helper is updated to pass the new parameters through so
it keeps compiling, with no new assertions of its own (`SplitView` adds
no new *rendering* decision, only threading).

- [ ] **Step 1: Write the failing arena-proof test**

`test/pane_view_test.dart` only imports `package:orthanc/pane_view.dart`
today — the new tests below reference `PaneBar.gripKey` and
`find.byType(PaneBar)` directly, so add
`import 'package:orthanc/pane_bar.dart';` alongside the file's existing
imports first.

In `test/pane_view_test.dart`, add `canDrag`/`onDragStart`/
`onDragUpdate`/`onDragEnd` to `pumpPaneView` (mirroring `pumpPaneBar`'s
Task 2 change), each defaulted the same no-op way `onToggleCollapse`/
`onExpand` already are:

```dart
    bool canDrag = false,
    void Function(String id)? onDragStart,
    void Function(String id, Offset globalPosition)? onDragUpdate,
    void Function(String id)? onDragEnd,
```

passed into the `PaneView(...)` constructor call alongside the existing
arguments, with the same `?? (_) {}` / `?? (_, _) {}` fallback shape
Task 2 used.

`pumpPaneView` fixes `canCollapse: false` today and hardcodes both
`onToggleCollapse: () {}` and `onExpand: () {}`, with no override for
either — the arena proof needs all three, so add `bool canCollapse =
false`, `VoidCallback? onToggleCollapse`, and `VoidCallback? onExpand`
to the helper's parameters, passed through to `PaneView(...)` the same
way `canDrag` was just added (`onToggleCollapse: onToggleCollapse ??
() {}`, `onExpand: onExpand ?? () {}`).

Step 3 below adds two more required `PaneView` fields, `isDropTarget`
and `isBeingDragged` — add both to `pumpPaneView` right now, fixed
`false`/`false`, so this helper (used by every test in the file, old and
new) doesn't stop compiling the moment Step 3 lands:

```dart
    isDropTarget: false,
    isBeingDragged: false,
```

Add these three tests after the existing focus-border tests:

```dart
  testWidgets('dragging the grip does not also toggle collapse', (
    tester,
  ) async {
    var toggled = false;

    await pumpPaneView(
      tester,
      focused: false,
      canDrag: true,
      canCollapse: true,
      onToggleCollapse: () => toggled = true,
    );
    await tester.drag(find.byKey(PaneBar.gripKey), const Offset(40, 0));

    expect(toggled, isFalse);
  });

  testWidgets('an ordinary tap on the bar still toggles collapse', (
    tester,
  ) async {
    var toggled = false;

    await pumpPaneView(
      tester,
      focused: false,
      canDrag: true,
      canCollapse: true,
      onToggleCollapse: () => toggled = true,
    );
    await tester.tap(find.byType(PaneBar));

    expect(toggled, isTrue);
  });

  testWidgets('an ordinary double-tap on the bar still expands', (
    tester,
  ) async {
    var expanded = false;

    await pumpPaneView(
      tester,
      focused: false,
      canDrag: true,
      canCollapse: true,
      onExpand: () => expanded = true,
    );
    await tester.tap(find.byType(PaneBar));
    await tester.tap(find.byType(PaneBar));

    expect(expanded, isTrue);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/pane_view_test.dart`
Expected: FAIL — `PaneView.canDrag` and friends are undefined; compile
error.

- [ ] **Step 3: Thread `canDrag` and the three callbacks through `PaneView`**

In `lib/pane_view.dart`, add to the `PaneView` constructor and fields
(after `onExpand`, current lines 36 and 79):

```dart
    required this.canDrag,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
```

```dart
  final bool canDrag;
  final void Function(String id) onDragStart;
  final void Function(String id, Offset globalPosition) onDragUpdate;
  final void Function(String id) onDragEnd;
```

Update `_paneBody`'s `PaneBar(...)` call (current lines 120–127) to pass
them through:

```dart
          child: PaneBar(
            session: widget.session,
            focused: widget.focused,
            accent: _accent,
            attentionAccent: _attentionAccent,
            canCollapse: widget.canCollapse,
            collapsed: widget.collapsed,
            canDrag: widget.canDrag,
            onDragStart: widget.onDragStart,
            onDragUpdate: widget.onDragUpdate,
            onDragEnd: widget.onDragEnd,
          ),
```

Add the drop-highlight overlay and dragged-pane dim, per the design's
"Drop feedback" section. `PaneView` needs one more input to know it is
the current hover target — add `required this.isDropTarget` and
`required this.isBeingDragged` alongside the four fields above:

```dart
  /// Whether a dragged pane is currently hovering over this one — paints
  /// the same style of overlay [focusBorderKey] does, in the drag
  /// accent, per the design's "Drop feedback" section.
  final bool isDropTarget;

  /// Whether this pane is the one currently being dragged — dims via a
  /// bare [Opacity] wrap rather than any layout change, so xterm never
  /// reflows mid-drag.
  final bool isBeingDragged;
```

Update `build` (current lines 90–112) to apply the dim and the new
overlay:

```dart
    return Listener(
      onPointerDown: (_) => widget.onFocus(),
      child: Opacity(
        opacity: widget.isBeingDragged ? 0.5 : 1.0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _paneBody(),
            if (widget.focused) _focusBorder(),
            if (!widget.focused && !widget.collapsed) _attentionBorder(),
            if (widget.isDropTarget) _dropHighlight(),
          ],
        ),
      ),
    );
```

Add `_dropHighlight`, beside `_focusBorder`/`_attentionBorder`:

```dart
  static const dropHighlightKey = Key('pane-drop-highlight');

  Widget _dropHighlight() => Positioned.fill(
    child: IgnorePointer(
      child: DecoratedBox(
        key: PaneView.dropHighlightKey,
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          border: Border.all(color: Colors.amber, width: 2),
        ),
      ),
    ),
  );
```

- [ ] **Step 4: Thread `canDrag`, the callbacks, and the two drag-state
      flags through `SplitView`**

In `lib/split_view.dart`, add to the `SplitView` constructor and fields
(after `onExpand`, current lines 34 and 59):

```dart
    required this.canDrag,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.dragSourceId,
    required this.dragHoverId,
```

```dart
  final bool canDrag;
  final void Function(String id) onDragStart;
  final void Function(String id, Offset globalPosition) onDragUpdate;
  final void Function(String id) onDragEnd;

  /// The pane currently being dragged, or null when no drag is in
  /// progress.
  final String? dragSourceId;

  /// The pane currently under the dragged pointer, or null.
  final String? dragHoverId;
```

Update `_shrinkablePane` (current lines 72–88) to pass them through:

```dart
  Widget _shrinkablePane(String sessionId) {
    final session = sessions[sessionId];
    if (session == null) return const SizedBox.shrink();
    return PaneView(
      session: session,
      focused: highlightFocus && sessionId == focusedId,
      onFocus: () => onFocus(sessionId),
      onKeyEvent: onKeyEvent,
      canCollapse: collapsibleIds.contains(sessionId),
      collapsed: collapsedIds.contains(sessionId),
      theme: theme,
      fontFamily: fontFamily,
      fontSize: fontSize,
      onToggleCollapse: () => onToggleCollapse(sessionId),
      onExpand: () => onExpand(sessionId),
      canDrag: canDrag,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      isBeingDragged: sessionId == dragSourceId,
      isDropTarget: sessionId == dragHoverId,
    );
  }
```

Update `_childSplitView` (current lines 204–221) to thread the same six
fields through the recursion, the same way `collapsedIds`/
`collapsibleIds` already are.

- [ ] **Step 5: Own the drag state in `WorkspaceView` and wire it into
      `build()`**

In `lib/workspace_view.dart`, add a `GlobalKey` field near `sessions`/
`workspace` (current lines 42–43):

```dart
  final _boundsKey = GlobalKey();
  String? _dragSourceId;
  String? _dragHoverId;
```

Add three methods just after `_expand` (current lines 130–133):

```dart
  void _onDragStart(String id) {
    setState(() => _dragSourceId = id);
  }

  void _onDragUpdate(String id, Offset globalPosition) {
    final target = _paneAt(globalPosition);
    final next = (target != null && target != id) ? target : null;
    if (next == _dragHoverId) return;
    setState(() => _dragHoverId = next);
  }

  void _onDragEnd(String id) {
    final target = _dragHoverId;
    setState(() {
      _dragSourceId = null;
      _dragHoverId = null;
      if (target != null) workspace = workspace.swap(id, target);
    });
  }

  /// The pane whose [Workspace.paneRects] rectangle contains
  /// [globalPosition], or null when the point falls outside every pane
  /// (the divider gutter, or off the tree entirely) — converted through
  /// [_boundsKey]'s own box into the same 0..1 fractional space
  /// [Workspace.paneRects] already speaks.
  String? _paneAt(Offset globalPosition) {
    final box = _boundsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return null;

    final local = box.globalToLocal(globalPosition);
    final fx = local.dx / box.size.width;
    final fy = local.dy / box.size.height;

    for (final entry in workspace.paneRects().entries) {
      final rect = entry.value;
      if (fx >= rect.left &&
          fx <= rect.right &&
          fy >= rect.top &&
          fy <= rect.bottom) {
        return entry.key;
      }
    }
    return null;
  }
```

Update `build()`'s `SplitView(...)` call (current lines 224–247) to wrap
it in the bounds key and pass the new parameters:

```dart
        return Focus(
          onKeyEvent: _onKey,
          child: Container(
            key: _boundsKey,
            child: SplitView(
              node: workspace.root,
              sessions: sessions,
              focusedId: workspace.focusedId,
              highlightFocus: workspace.isSplit,
              collapsedIds: workspace.collapsedIds,
              collapsibleIds: workspace.collapsibleIds,
              theme: terminalThemeFor(settings.colorScheme),
              fontFamily: terminalFontFamilyName(settings.fontFamily),
              fontSize: clampFontSize(
                settings.fontSize ?? defaultTerminalFontSize,
              ),
              onFocus: _onPaneFocus,
              onKeyEvent: _onKey,
              onToggleCollapse: _toggleCollapse,
              onExpand: _expand,
              onResize: (split, index, delta) => setState(() {
                workspace = workspace.resizeSplit(
                  split: split,
                  dividerIndex: index,
                  delta: delta,
                );
              }),
              canDrag: workspace.isSplit,
              onDragStart: _onDragStart,
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
              dragSourceId: _dragSourceId,
              dragHoverId: _dragHoverId,
            ),
          ),
        );
```

- [ ] **Step 6: Update `test/split_view_test.dart`'s `pumpSplitView`
      helper so it keeps compiling**

Add the same six parameters to `pumpSplitView` and its `SplitView(...)`
call, defaulted the same no-op way the existing `onFocus`/`onResize`/
`onToggleCollapse`/`onExpand` defaults already are (`canDrag: false`,
`dragSourceId: null`, `dragHoverId: null`, the three callbacks `(_) {}`/
`(_, _) {}`). No new assertions are owed here — `split_view_test.dart`
tests focus-border marking, not drag; Task 3's own arena proof lives in
`pane_view_test.dart` (Step 1 above).

- [ ] **Step 7: Run the full test suite**

Run: `fvm flutter test`
Expected: PASS — every unit and widget test in the project.

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/pane_view.dart lib/split_view.dart lib/workspace_view.dart \
  test/pane_view_test.dart test/split_view_test.dart
git commit -m "Wire pane drag end to end: grip, drop highlight, and swap on release"
```

---

### Task 4: Manual verification, both platforms

**Files:** none (verification only).

- [ ] **Step 1: Launch on Windows**

Run: `fvm flutter run -d windows`
Expected: app builds and launches with no console errors.

- [ ] **Step 2: Drag one pane onto another and confirm the swap**

Split into at least three panes. Press the grip on one pane's bar and
drag it onto a different pane; release.
Expected: the two sessions trade places — each keeps its own slot's
size, not the size it arrived with. The dragged session's pane is now
focused.

- [ ] **Step 3: Confirm the drop highlight and dim**

Repeat the drag slowly, pausing mid-drag over a target pane before
releasing.
Expected: the pane being dragged dims; the pane under the pointer shows
the amber highlight; moving over a third pane shifts the highlight to
it, dropping the previous one.

- [ ] **Step 4: Confirm dropping on empty space or the same pane is a
      no-op**

Drag a pane's grip and release over the divider gutter between two
panes; separately, drag a pane's grip a short distance and release still
over its own pane.
Expected: nothing changes in either case.

- [ ] **Step 5: Confirm a collapsed pane's stale flag doesn't survive a
      swap that makes it illegal**

Build a column with 2+ rows, collapse one row, then drag a pane from
outside that column onto the collapsed one.
Expected: the swap completes; if the collapsed pane's new position no
longer qualifies for collapse (a row split, for instance), it renders
expanded, not as a stray bar.

- [ ] **Step 6: Confirm the existing bar gestures are untouched**

With the grip present, tap a bar to collapse/expand it, double-click to
maximize, and right-click to rename.
Expected: all three behave exactly as before Task 2–3 landed.

- [ ] **Step 7: Repeat the launch and the same checks on macOS**

Run: `fvm flutter run -d macos`
Expected: all of Steps 2–6 hold identically.

- [ ] **Step 8: Run the full automated suite one last time**

Run: `fvm flutter test`
Expected: PASS, same as Task 3's final check — confirms nothing drifted
between the last commit and the manual walk.

# Pane Move & Re-split (Layer 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A drop on the edge of a target pane lifts the dragged pane out
of the tree and re-splices it in on that side; a drop on the target's
centre still swaps, exactly as layer 1 shipped. Layer 2 only — no
change to swap's own behavior beyond the one shared refactor named
below.

**Architecture:** `PaneRect` gains `zoneAt(x, y)`, a pure geometry
function picking the nearest edge or `null` for the centre dead-zone.
`Workspace` gains `move({sourceId, targetId, side})`, built from two new
anchor-generalized private helpers (`_insertAdjacent`/`_wrapAdjacent`)
that mirror `split()`'s existing insert logic without touching it.
`close()` and `swap()`'s duplicated collapse-cleanup sequence is lifted
into one shared `_reconciledCollapse` first, so `move()` is the third
caller of something that already exists rather than a fourth
near-duplicate. `WorkspaceView`/`PaneView` gain a `Direction? dropSide`
alongside the existing hover-tracking, deciding swap-vs-move on release
and rendering a second, edge-shaped highlight beside the existing
full-pane one.

**Tech Stack:** Flutter/Dart, `flutter_test`. Widget tests exist for
`PaneView` in this codebase (added for layer 1) — `PaneRect`/
`Workspace` stay pure unit tests, no engine.

## Global Constraints

- Every `Workspace` operation stays immutable — return a new
  `Workspace`, never mutate `this`.
- `_insertAdjacent`/`_wrapAdjacent` are **new** methods — do not edit
  `_insertBeside`, `_wrapFocusedChild`, `_insertSibling`,
  `_recurseBesideInChildren`, or `_wrapInSplit`. Unifying them is a
  named, deliberately deferred follow-up (see the design spec's
  Decision 3 and Deferred section) — touching them here is out of
  scope.
- Task 1's refactor must not change `close()`'s or `swap()`'s observable
  behavior at all — its own step 2 (run the full existing suite) is the
  gate for that, before any new code is written on top of it.
- Match existing test style exactly: `group`/`test`, a named `expected`
  constant declared before the call, then one assertion comparing
  against it.

---

### Task 1: Extract `_reconciledCollapse`; migrate `close()` and `swap()`

**Files:**
- Modify: `lib/workspace.dart`
- Test: `test/workspace_test.dart` (no new tests — this task's own gate
  is that every *existing* test still passes)

**Interfaces:**
- Produces: `Workspace._reconciledCollapse(LayoutNode newRoot, Set<String> prior) -> Set<String>`.
- Consumes: existing `_collectCollapsible`, `_releaseEmptiedColumns`.

- [ ] **Step 1: Extract the helper**

In `lib/workspace.dart`, add just after `_releaseEmptiedColumns` (which
currently ends the `close()`-related group, right before `swap`):

```dart
  /// The collapse entries that survive a structural change to [newRoot]:
  /// any entry no longer collapsible in the new tree is dropped, and any
  /// column [newRoot] would otherwise leave holding nothing but bars is
  /// released back to even shares. Shared by [close], [swap], and [move]
  /// — the one place this invariant is enforced.
  Set<String> _reconciledCollapse(LayoutNode newRoot, Set<String> prior) {
    final collapsibleAfter = <String>{};
    _collectCollapsible(newRoot, collapsibleAfter);
    final kept = prior.intersection(collapsibleAfter);
    _releaseEmptiedColumns(newRoot, kept);
    return kept;
  }
```

- [ ] **Step 2: Migrate `close()`**

Replace `close()` and delete `_survivingCollapsed` entirely (both
currently sit together, `close()` first):

```dart
  Workspace? close(String sessionId) {
    final remaining = _without(root, sessionId);
    if (remaining == null) return null;

    final ids = _idsOf(remaining);

    return Workspace(
      root: remaining,
      focusedId: ids.contains(focusedId) ? focusedId : ids.first,
      collapsedIds: _reconciledCollapse(remaining, collapsedIds),
    );
  }
```

Note what's *not* here any more: `_survivingCollapsed`'s
`.where((id) => id != closedId)` step. This is a provably no-op removal
— `collapsibleAfter` is collected from `remaining`, which no longer
contains `sessionId` at all, so `sessionId` could never survive the
`.intersection(collapsibleAfter)` step regardless. Step 4 below is what
proves this: every existing `close()` collapse test must still pass
unchanged.

- [ ] **Step 3: Migrate `swap()`**

Replace `swap()`'s body (keep its signature and doc comment as-is):

```dart
  Workspace swap(String sourceId, String targetId) {
    if (sourceId == targetId) return this;

    final swapped = _swapped(root, sourceId, targetId);

    return Workspace(
      root: swapped,
      focusedId: sourceId,
      collapsedIds: _reconciledCollapse(swapped, collapsedIds),
    );
  }
```

- [ ] **Step 4: Run the full existing suite to verify nothing regressed**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — every existing test, `Workspace.close`'s collapse
group and `Workspace.swap`'s collapse group both included, unchanged.
This is the task's real verification; no new test is added because
none is needed — the existing suite already covers the behavior this
step promises not to change.

- [ ] **Step 5: Commit**

```bash
git add lib/workspace.dart
git commit -m "Extract _reconciledCollapse, shared by close() and swap()"
```

---

### Task 2: `PaneRect.zoneAt` — the drop-zone geometry

**Files:**
- Modify: `lib/layout_node.dart`
- Test: `test/layout_node_test.dart`

**Interfaces:**
- Produces: `const dropEdgeBand = 0.25`, `PaneRect.zoneAt(double x, double y) -> Direction?`.

- [ ] **Step 1: Write the failing tests**

`test/layout_node_test.dart` today holds three bare top-level `test()`s
with no `group`. Add a new `group` after them, before the file's
closing `}`:

```dart
  group('PaneRect.zoneAt', () {
    const rect = PaneRect(left: 0.25, top: 0.25, width: 0.5, height: 0.5);

    test('the centre is the dead zone', () {
      const expected = null;

      final zone = rect.zoneAt(0.5, 0.5);

      expect(zone, expected);
    });

    test('a point near the left edge picks left', () {
      const expected = Direction.left;

      final zone = rect.zoneAt(0.26, 0.5);

      expect(zone, expected);
    });

    test('a point near the right edge picks right', () {
      const expected = Direction.right;

      final zone = rect.zoneAt(0.74, 0.5);

      expect(zone, expected);
    });

    test('a point near the top edge picks up', () {
      const expected = Direction.up;

      final zone = rect.zoneAt(0.5, 0.26);

      expect(zone, expected);
    });

    test('a point near the bottom edge picks down', () {
      const expected = Direction.down;

      final zone = rect.zoneAt(0.5, 0.74);

      expect(zone, expected);
    });

    test('exactly at the band boundary still counts as the centre', () {
      const expected = null;

      // Local x = (0.375 - 0.25) / 0.5 = 0.25, exactly dropEdgeBand from
      // the left edge — the comparison is strict, so the boundary itself
      // belongs to the centre, not the edge.
      final zone = rect.zoneAt(0.375, 0.5);

      expect(zone, expected);
    });

    test('a corner picks a deterministic edge, not the centre', () {
      const expected = Direction.left;

      // Local (0, 0) — equidistant from left and up. left wins the tie.
      final zone = rect.zoneAt(0.25, 0.25);

      expect(zone, expected);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/layout_node_test.dart`
Expected: FAIL — `dropEdgeBand` and `PaneRect.zoneAt` are undefined.

- [ ] **Step 3: Implement `zoneAt`**

In `lib/layout_node.dart`, add a top-level constant just after the
`Direction` enum (current line 14):

```dart
/// How close to a pane's own edge a drop must land to mean "insert here"
/// rather than "swap" — a fraction of that pane's own width or height.
const dropEdgeBand = 0.25;
```

Add a method inside the `PaneRect` class, after its existing getters
(`right`/`bottom`/`centerX`/`centerY`, current lines 30–33):

```dart
  /// Which edge of this rect [x]/[y] (both fractions of the whole
  /// window, the same space [Workspace.paneRects] returns) sits closest
  /// to — or null when every edge is farther than [dropEdgeBand], the
  /// centre dead-zone where a drop means swap rather than insert.
  ///
  /// [x]/[y] are expected to already fall within this rect; a point
  /// exactly on the boundary is clamped rather than trusted, since the
  /// caller's own hit-test is what guarantees the point belongs here at
  /// all. A corner equidistant from two edges picks a fixed order —
  /// left, then right, then up, then down — arbitrary by design; see
  /// the design spec's "Watch out".
  Direction? zoneAt(double x, double y) {
    final localX = ((x - left) / width).clamp(0.0, 1.0);
    final localY = ((y - top) / height).clamp(0.0, 1.0);

    final distances = {
      Direction.left: localX,
      Direction.right: 1 - localX,
      Direction.up: localY,
      Direction.down: 1 - localY,
    };
    final nearest = distances.entries.reduce(
      (a, b) => a.value <= b.value ? a : b,
    );
    return nearest.value < dropEdgeBand ? nearest.key : null;
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/layout_node_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/layout_node.dart test/layout_node_test.dart
git commit -m "Add PaneRect.zoneAt, the drop-zone geometry for pane move"
```

---

### Task 3: `Workspace.move`

**Files:**
- Modify: `lib/workspace.dart`
- Test: `test/workspace_test.dart`

**Interfaces:**
- Consumes: `_without`, `_reconciledCollapse` (Task 1).
- Produces: `Workspace.move({required String sourceId, required String targetId, required Direction side}) -> Workspace`.

- [ ] **Step 1: Write the failing tests**

Add a new group at the end of `test/workspace_test.dart`, after
`group('Workspace.swap', ...)`, before the file's closing `}`:

```dart
  group('Workspace.move', () {
    test('inserts as a sibling after the target when the parent already '
        'runs that axis', () {
      final expected = ['b', 'a', 'c'];

      // row[a, b, c] — move 'a' onto 'b's right edge.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .move(sourceId: 'a', targetId: 'b', side: Direction.right);

      expect(workspace.sessionIds, expected);
    });

    test('inserts as a sibling before the target when the parent already '
        'runs that axis', () {
      final expected = ['a', 'c', 'b'];

      // row[a, b, c] — move 'c' onto 'b's left edge: 'c' relocates to
      // sit directly before 'b', not simply back where it already was.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .move(sourceId: 'c', targetId: 'b', side: Direction.left);

      expect(workspace.sessionIds, expected);
    });

    test('wraps the target in a new split when the parent runs the other '
        'axis', () {
      // column[a, b] — move 'a' onto 'b's right edge: 'b's own parent is
      // a column, the wrong axis for a left/right drop, so 'b' is
      // wrapped in a fresh row.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .move(sourceId: 'a', targetId: 'b', side: Direction.right);

      final root = workspace.root as SplitNode;
      expect(root.axis, SplitAxis.row);
      expect(root.children.length, 2);
      expect((root.children[0] as PaneNode).sessionId, 'b');
      expect((root.children[1] as PaneNode).sessionId, 'a');
    });

    test('wraps a target while an untouched sibling stays where it was', () {
      // row[a, b, c] — move 'a' onto 'c's top edge. 'c's own parent (the
      // row) runs the wrong axis for an up/down drop, so 'c' alone is
      // wrapped in a fresh column; 'b' stays exactly where it was, as
      // the row's other child.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .move(sourceId: 'a', targetId: 'c', side: Direction.up);

      final root = workspace.root as SplitNode;
      expect(root.axis, SplitAxis.row);
      expect(root.children.length, 2);
      expect((root.children[0] as PaneNode).sessionId, 'b');
      final nested = root.children[1] as SplitNode;
      expect(nested.axis, SplitAxis.column);
      expect((nested.children[0] as PaneNode).sessionId, 'a');
      expect((nested.children[1] as PaneNode).sessionId, 'c');
    });

    test('the dissolve case: dropped back on its own only sibling, same '
        'side, reconstructs the original order', () {
      final expected = ['a', 'b'];

      // row[a, b] — move 'a' onto 'b's own left edge (where 'a' already
      // was). Removing 'a' dissolves the split down to bare 'b'; the
      // insert re-finds 'b' fresh and wraps it, landing back where it
      // started.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .move(sourceId: 'a', targetId: 'b', side: Direction.left);

      expect(workspace.sessionIds, expected);
    });

    test('the dissolve case: dropped on the opposite side reorders the '
        'pair', () {
      final expected = ['b', 'a'];

      // row[a, b] — move 'a' onto 'b's right edge this time.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .move(sourceId: 'a', targetId: 'b', side: Direction.right);

      expect(workspace.sessionIds, expected);
    });

    test('re-evens ratios at the landing split rather than keeping a '
        'prior drag', () {
      final expected = [1 / 3, 1 / 3, 1 / 3];

      // row[a, b, c], then the a|b divider dragged uneven. Moving 'c'
      // onto 'a's right edge lands back in the same row, which
      // re-evens via evenRatios regardless of what the drag left
      // behind.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c');
      final resized = workspace.resizeSplit(
        split: workspace.root,
        dividerIndex: 0,
        delta: 0.1,
      );
      final moved = resized.move(
        sourceId: 'c',
        targetId: 'a',
        side: Direction.right,
      );

      expect((moved.root as SplitNode).ratios, expected);
    });

    test('is a no-op when source and target are the same id', () {
      final expected = ['a', 'b'];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .move(sourceId: 'a', targetId: 'a', side: Direction.right);

      expect(workspace.sessionIds, expected);
    });

    test('is a no-op when either id is missing from the tree', () {
      final expected = ['a', 'b'];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .move(sourceId: 'z', targetId: 'b', side: Direction.right);

      expect(workspace.sessionIds, expected);
    });

    test('focuses the moved pane', () {
      const expected = 'a';

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .focus('c')
          .move(sourceId: 'a', targetId: 'b', side: Direction.right);

      expect(workspace.focusedId, expected);
    });

    test('drops a collapse entry the move leaves illegal', () {
      final expected = <String>{};

      // column[a, b], with 'b' collapsed. Moving 'b' onto 'a's right
      // edge wraps 'a' in a fresh row holding 'a' and 'b' — 'b's new
      // parent is a row, where collapse is never legal.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b')
          .move(sourceId: 'b', targetId: 'a', side: Direction.right);

      expect(workspace.collapsedIds, expected);
    });

    test('leaves an unrelated pane\'s collapse entry alone', () {
      final expected = {'d'};

      // (a over b) | (c over d), with 'd' collapsed. Moving 'a' onto
      // 'b's own right edge (elsewhere entirely) must not touch 'd's
      // entry — move never changes a branch it doesn't reach into.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .split(axis: SplitAxis.column, newSessionId: 'd')
          .toggleCollapse('d')
          .move(sourceId: 'a', targetId: 'b', side: Direction.right);

      expect(workspace.collapsedIds, expected);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — `Workspace.move` is undefined.

- [ ] **Step 3: Implement `move`, `_insertAdjacent`, `_wrapAdjacent`**

In `lib/workspace.dart`, add just after `swap`/`_swapped` (which Task 1
left otherwise untouched):

```dart
  /// Lifts [sourceId] out of the tree and re-splices it in beside
  /// [targetId], on the side [side] names — `left`/`up` land before the
  /// target, `right`/`down` land after. A no-op when [sourceId] and
  /// [targetId] are the same id, or when either is absent from the
  /// tree. Focuses [sourceId] wherever it lands, same convention as
  /// [swap]/[split]/[toggleCollapse].
  ///
  /// Removal runs first, via the existing [_without] — including
  /// whatever split dissolution that triggers — and only then does the
  /// insert step search the tree that remains for [targetId]. A split
  /// that disappeared during removal was never a valid landing spot, so
  /// searching fresh is what keeps that case from needing any special
  /// handling at all.
  ///
  /// Collapse cleanup runs through the same [_reconciledCollapse] both
  /// [close] and [swap] already use.
  Workspace move({
    required String sourceId,
    required String targetId,
    required Direction side,
  }) {
    if (sourceId == targetId) return this;
    final ids = sessionIds;
    if (!ids.contains(sourceId) || !ids.contains(targetId)) return this;

    final axis = switch (side) {
      Direction.left || Direction.right => SplitAxis.row,
      Direction.up || Direction.down => SplitAxis.column,
    };
    final before = side == Direction.left || side == Direction.up;

    final removed = _without(root, sourceId)!;
    final inserted = _insertAdjacent(
      removed,
      targetId,
      axis,
      sourceId,
      before: before,
    );

    return Workspace(
      root: inserted,
      focusedId: sourceId,
      collapsedIds: _reconciledCollapse(inserted, collapsedIds),
    );
  }

  /// Same two rules as [_insertBeside], generalized to an explicit
  /// [anchorId] and an explicit [before]/after, rather than always
  /// [focusedId] and always after — kept as its own implementation
  /// rather than folded into [_insertBeside]'s; see the design spec's
  /// Decision 3 for why.
  static LayoutNode _insertAdjacent(
    LayoutNode node,
    String anchorId,
    SplitAxis axis,
    String newSessionId, {
    required bool before,
  }) {
    if (node is PaneNode) {
      if (node.sessionId != anchorId) return node;
      return _wrapAdjacent(node, axis, newSessionId, before: before);
    }

    final split = node as SplitNode;
    final at = split.children.indexWhere(
      (child) => child is PaneNode && child.sessionId == anchorId,
    );

    if (at != -1 && split.axis == axis) {
      final children = [...split.children]
        ..insert(before ? at : at + 1, PaneNode(newSessionId));
      return SplitNode(
        axis: axis,
        children: children,
        ratios: evenRatios(children.length),
      );
    }

    if (at != -1) {
      final children = [...split.children];
      children[at] = _wrapAdjacent(
        children[at],
        axis,
        newSessionId,
        before: before,
      );
      return SplitNode(
        axis: split.axis,
        children: children,
        ratios: split.ratios,
      );
    }

    return SplitNode(
      axis: split.axis,
      children: [
        for (final child in split.children)
          _insertAdjacent(child, anchorId, axis, newSessionId, before: before),
      ],
      ratios: split.ratios,
    );
  }

  static LayoutNode _wrapAdjacent(
    LayoutNode node,
    SplitAxis axis,
    String newSessionId, {
    required bool before,
  }) {
    return SplitNode(
      axis: axis,
      children: before
          ? [PaneNode(newSessionId), node]
          : [node, PaneNode(newSessionId)],
      ratios: evenRatios(2),
    );
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — all new and existing tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/workspace.dart test/workspace_test.dart
git commit -m "Add Workspace.move for lifting a pane out and re-splicing it beside a target"
```

---

### Task 4: `PaneView`, `WorkspaceView` — wired end to end

**Why one task:** `PaneView` requires a `dropSide` argument only
`WorkspaceView` can supply; `WorkspaceView` requires `move`/`zoneAt`
from Tasks 2–3. Same shape as layer 1's own final wiring task.

**Files:**
- Modify: `lib/pane_view.dart`
- Modify: `lib/split_view.dart`
- Modify: `lib/workspace_view.dart`
- Test: `test/pane_view_test.dart`

**Interfaces:**
- Consumes: `Workspace.move` (Task 3), `PaneRect.zoneAt` (Task 2).
- Produces: the fully wired edge-insert behavior — nothing later
  depends on this task.

- [ ] **Step 1: Write the failing tests for the edge-band overlay**

`test/pane_view_test.dart` has no reason to import `layout_node.dart`
today — `Direction` is about to change that. Add
`import 'package:orthanc/layout_node.dart';` alongside the file's
existing imports first.

`pumpPaneView` currently hardcodes `isDropTarget: false` and has no
`dropSide` field at all — layer 1 never needed either overridable. Add
`bool isDropTarget = false` and `Direction? dropSide` to the helper's
parameters, both passed straight through to `PaneView(...)`.

Add these three tests near the existing border tests:

```dart
  testWidgets('a full-pane highlight appears when hovered with no side', (
    tester,
  ) async {
    await pumpPaneView(tester, focused: false, isDropTarget: true);

    expect(find.byKey(PaneView.dropHighlightKey), findsOneWidget);
    expect(find.byKey(PaneView.dropEdgeKey), findsNothing);
  });

  testWidgets('an edge band appears instead when hovered with a side', (
    tester,
  ) async {
    await pumpPaneView(
      tester,
      focused: false,
      isDropTarget: true,
      dropSide: Direction.left,
    );

    expect(find.byKey(PaneView.dropEdgeKey), findsOneWidget);
    expect(find.byKey(PaneView.dropHighlightKey), findsNothing);
  });

  testWidgets('neither highlight appears when not a drop target', (
    tester,
  ) async {
    await pumpPaneView(tester, focused: false);

    expect(find.byKey(PaneView.dropHighlightKey), findsNothing);
    expect(find.byKey(PaneView.dropEdgeKey), findsNothing);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/pane_view_test.dart`
Expected: FAIL — `PaneView.dropSide`, `isDropTarget` override, and
`PaneView.dropEdgeKey` are all undefined/missing.

- [ ] **Step 3: Add `dropSide` and the edge-band overlay to `PaneView`**

`lib/pane_view.dart` has no reason to import `layout_node.dart` today
— `Direction` is about to change that. Add
`import 'layout_node.dart';` alongside the file's existing imports
first.

In `lib/pane_view.dart`, add `required this.dropSide` to the
constructor, alongside the existing `isDropTarget`/`isBeingDragged`
fields added in the layer-1 plan:

```dart
  /// Which edge of this pane the drag is currently hovering, when
  /// [isDropTarget] is true — null means the centre dead-zone (today's
  /// full-pane swap highlight applies instead).
  final Direction? dropSide;

  static const dropEdgeKey = Key('pane-drop-edge');
```

Update `build`'s overlay list — the existing
`if (widget.isDropTarget) _dropHighlight()` becomes:

```dart
            if (widget.isDropTarget)
              widget.dropSide == null ? _dropHighlight() : _dropEdge(),
```

Add `_dropEdge` beside `_dropHighlight`. Built on `Align` rather than
`Positioned`'s own left/right/top/bottom+width/height combination —
`Positioned` asserts against setting an explicit `height` alongside
both `top` and `bottom` (and the same for `width` alongside `left` and
`right`), which a same-shaped `Positioned`-only version of this would
need to do for the two edges perpendicular to the band:

```dart
  Widget _dropEdge() {
    final side = widget.dropSide!;
    final horizontal = side == Direction.left || side == Direction.right;
    return Positioned.fill(
      child: Align(
        alignment: switch (side) {
          Direction.left => Alignment.centerLeft,
          Direction.right => Alignment.centerRight,
          Direction.up => Alignment.topCenter,
          Direction.down => Alignment.bottomCenter,
        },
        child: FractionallySizedBox(
          widthFactor: horizontal ? dropEdgeBand : 1,
          heightFactor: horizontal ? 1 : dropEdgeBand,
          child: IgnorePointer(
            child: DecoratedBox(
              key: PaneView.dropEdgeKey,
              decoration: BoxDecoration(
                color: Colors.lightBlueAccent.withValues(alpha: 0.2),
                border: Border.all(color: Colors.lightBlueAccent, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 4: Thread `dropSide` through `SplitView`**

In `lib/split_view.dart`, add `final Direction? dragHoverSide;` beside
the existing `dragHoverId` field, and pass it into `PaneView(...)` in
`_shrinkablePane`:

```dart
      dropSide: sessionId == dragHoverId ? dragHoverSide : null,
```

Thread `dragHoverSide` through `_childSplitView`'s recursive call, the
same way `dragHoverId` already is.

- [ ] **Step 5: Own `_dragHoverSide` in `WorkspaceView`, decide swap vs. move on release**

In `lib/workspace_view.dart`, add a field beside `_dragHoverId`:

```dart
  Direction? _dragHoverSide;
```

Update `_onDragUpdate` to compute it once a hover pane is found:

```dart
  void _onDragUpdate(String id, Offset globalPosition) {
    final target = _paneAt(globalPosition);
    final next = (target != null && target != id) ? target : null;
    final side = next == null
        ? null
        : _sideAt(next, globalPosition);
    if (next == _dragHoverId && side == _dragHoverSide) return;
    setState(() {
      _dragHoverId = next;
      _dragHoverSide = side;
    });
  }

  /// The drop zone within [paneId]'s own rect that [globalPosition]
  /// falls in, converted through the same [_boundsKey] box [_paneAt]
  /// already uses.
  Direction? _sideAt(String paneId, Offset globalPosition) {
    final box = _boundsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return null;
    final local = box.globalToLocal(globalPosition);
    final rect = workspace.paneRects()[paneId];
    if (rect == null) return null;
    return rect.zoneAt(local.dx / box.size.width, local.dy / box.size.height);
  }
```

Update `_onDragEnd` to branch on the recorded side:

```dart
  void _onDragEnd(String id) {
    final target = _dragHoverId;
    final side = _dragHoverSide;
    setState(() {
      _dragSourceId = null;
      _dragHoverId = null;
      _dragHoverSide = null;
      if (target == null) return;
      workspace = side == null
          ? workspace.swap(id, target)
          : workspace.move(sourceId: id, targetId: target, side: side);
    });
  }
```

Update `build()`'s `SplitView(...)` call to pass `dragHoverSide:
_dragHoverSide`.

- [ ] **Step 6: Run the full test suite**

Run: `fvm flutter test`
Expected: PASS — every unit and widget test in the project.

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/pane_view.dart lib/split_view.dart lib/workspace_view.dart \
  test/pane_view_test.dart
git commit -m "Wire pane move end to end: edge-band highlight, swap-vs-move on release"
```

---

### Task 5: Manual verification, both platforms

**Files:** none (verification only).

- [ ] **Step 1: Launch on Windows, then macOS**

Run: `fvm flutter run -d windows` (then repeat on macOS)
Expected: app builds and launches with no console errors.

- [ ] **Step 2: Confirm all five zones**

Split into 3+ panes. Drag one pane's label and hover each edge and the
centre of a different target pane in turn.
Expected: the highlight shape changes as the pointer crosses each
`dropEdgeBand` boundary — full-pane amber in the centre, a thin blue
band on whichever edge is nearest elsewhere.

- [ ] **Step 3: Confirm a same-axis edge drop reorders in place**

In a flat row of 3+ panes, drag the first pane onto the right edge of
the middle one.
Expected: the dragged pane lands directly after the middle one; no new
split appears — matches Frame C of the wireframe.

- [ ] **Step 4: Confirm a cross-axis edge drop wraps the target**

Drag a pane from one column onto the top or bottom edge of a pane in a
different row.
Expected: the target is wrapped in a new split of the dropped axis; the
tree visibly deepens by one level there.

- [ ] **Step 5: Confirm the dissolve case**

With exactly two panes side by side, drag one onto the other's near
edge (the side it's already adjacent from), then onto the far edge.
Expected: the near-edge drop leaves the order unchanged (sizes reset to
even); the far-edge drop reorders the pair.

- [ ] **Step 6: Confirm collapse cleanup**

Collapse a row in a multi-row column, then drag a pane from outside
that column onto one of the collapsed row's edges.
Expected: the moved pane lands correctly; if its new position no longer
qualifies for collapse, it renders expanded, not as a stray bar.

- [ ] **Step 7: Confirm swap still works exactly as before**

Drag a pane onto another's centre.
Expected: unchanged from layer 1 — the two trade places, sizes stay
with their slots.

- [ ] **Step 8: Run the full automated suite one last time**

Run: `fvm flutter test`
Expected: PASS, confirming nothing drifted between the last commit and
the manual walk.

# Orthanc Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Many Claude Code sessions running at once in one window, arranged as split panes by hotkey, each pane titled by its own program and showing a spinner while it works.

**Architecture:** The layout lives in a plain immutable tree (`Workspace` over `LayoutNode`) that knows nothing of Flutter and holds only session *ids*. Every arrangement operation — split, close, resize, directional focus — is a pure function over that tree, unit-tested with no engine and no live process. A separate `Sessions` registry owns the living `Session` objects, each holding one `Pty` and one `Terminal`. Widgets walk the tree and draw it, holding no layout logic. Milestone 0's proven pty wiring is moved into `Session` essentially unchanged, not rewritten.

**Tech Stack:** Flutter desktop (macOS + Windows), `flutter_pty` 0.4.2, `xterm` 4.0.0 (pinned to the `orthanc-integration` fork), `flutter_test`.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-21-orthanc-milestone-1-design.md`. Every decision there is binding; this plan implements it and adds nothing.
- Platforms: macOS and Windows only. Linux is not a target.
- Do not rewrite Milestone 0's pty/terminal wiring while restructuring around it. `_spawn()`, `_wire()` and `_reportExit()` move into `Session` with their comments intact; their bodies change only where this plan says so.
- `xterm` stays pinned to `dependency_overrides` at `a766197d21a516d7e949bb095acbea2b0b707e09`. Do not unpin it; PRs #230 and #231 are still open upstream.
- The spawned command stays `shellCommand()` for **every** pane. Per-pane commands are deferred; do not add a command parameter, flag, or setting.
- Busy threshold starts at **500ms**, named as a constant, adjusted only against a running app.
- Hotkeys, exactly as specified — macOS: `Cmd+D` split vertical, `Cmd+Shift+D` split horizontal, `Cmd+W` close, `Cmd+Opt+arrows` move focus. Windows: `Alt+Shift+Plus`, `Alt+Shift+Minus`, `Ctrl+Shift+W`, `Alt+arrows`. `Ctrl+D` must never be bound — it is EOF.
- Splits start even: after any split, that node's ratios are redistributed equally across its children.
- Deferred, do not build: card grid, expand/collapse, hand-naming sessions, restart/respawn, per-pane commands, layout persistence, any "needs attention" signal.
- The enum is named `SplitAxis`, not `Axis`, to avoid colliding with Flutter's `Axis` in widget files that import both.

## File Structure

| File | Responsibility |
|---|---|
| `lib/layout_node.dart` | `SplitAxis`, `Direction`, `PaneRect`, sealed `LayoutNode` / `PaneNode` / `SplitNode`. No Flutter import. |
| `lib/workspace.dart` | Immutable `Workspace`: split, close, resize, neighbour, paneRects. No Flutter import. |
| `lib/split_shortcuts.dart` | Pure per-platform hotkey map, in the shape of `shell_command.dart`. |
| `lib/session.dart` | `Session` — owns one `Pty` + `Terminal`, tracks title and busy. Outlives widgets. |
| `lib/sessions.dart` | `Sessions` — spawns, holds and disposes sessions by id. |
| `lib/pane_bar.dart` | The 14px title bar: spinner slot + title. |
| `lib/pane_view.dart` | One pane: `PaneBar` above a `TerminalView`. Replaces `PtyTerminal`. |
| `lib/split_view.dart` | Recursive rendering of a `LayoutNode`, with draggable dividers. |
| `lib/workspace_view.dart` | Holds `Workspace` + `Sessions` state; intercepts hotkeys; handles session exit. |
| `lib/main.dart` | Modified: hosts `WorkspaceView` instead of `PtyTerminal`. |
| `lib/pty_terminal.dart` | **Deleted** in Task 9, its wiring having moved to `Session` and `PaneView`. |

---

## Task 1: Layout tree types

**Files:**
- Create: `lib/layout_node.dart`, `test/layout_node_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum SplitAxis { row, column }`; `enum Direction { left, right, up, down }`; `class PaneRect` with `final double left, top, width, height` and a const constructor plus value equality; `sealed class LayoutNode`; `class PaneNode extends LayoutNode` with `final String sessionId`; `class SplitNode extends LayoutNode` with `final SplitAxis axis`, `final List<LayoutNode> children`, `final List<double> ratios`. Every later task builds on these exact names.

- [ ] **Step 1: Write the failing test**

Create `test/layout_node_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/layout_node.dart';

void main() {
  test('a pane node carries its session id', () {
    const expected = 'a';

    const node = PaneNode(expected);

    expect(node.sessionId, expected);
  });

  test('a split node carries its axis, children and ratios', () {
    const expectedAxis = SplitAxis.row;
    const expectedChildren = [PaneNode('a'), PaneNode('b')];
    const expectedRatios = [0.5, 0.5];

    const node = SplitNode(
      axis: expectedAxis,
      children: expectedChildren,
      ratios: expectedRatios,
    );

    expect(node.axis, expectedAxis);
    expect(node.children, expectedChildren);
    expect(node.ratios, expectedRatios);
  });

  test('pane rects of the same numbers are equal', () {
    const expected = PaneRect(left: 0, top: 0, width: 0.5, height: 1);

    const actual = PaneRect(left: 0, top: 0, width: 0.5, height: 1);

    expect(actual, expected);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/layout_node_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/layout_node.dart'`.

- [ ] **Step 3: Implement the types**

Create `lib/layout_node.dart`:

```dart
/// The arrangement of panes, as plain data.
///
/// Nothing here imports Flutter, and nothing here holds a [Session] — only its
/// id. That is what lets every layout operation be exercised by a unit test
/// with no engine and no live process, which the pty wiring itself can never be.

/// Which way a split lays its children out.
///
/// Named [SplitAxis] rather than `Axis` because widget files import Flutter's
/// `Axis` alongside this.
enum SplitAxis { row, column }

/// A direction to look in for a neighbouring pane.
enum Direction { left, right, up, down }

/// A pane's share of the window, in fractions of the whole.
class PaneRect {
  const PaneRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  @override
  bool operator ==(Object other) =>
      other is PaneRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'PaneRect($left, $top, $width, $height)';
}

/// One node of the layout: either a pane, or a split holding more nodes.
sealed class LayoutNode {
  const LayoutNode();
}

/// A leaf — one session's place in the window.
class PaneNode extends LayoutNode {
  const PaneNode(this.sessionId);

  final String sessionId;
}

/// A division. [ratios] runs parallel to [children] and sums to 1.
class SplitNode extends LayoutNode {
  const SplitNode({
    required this.axis,
    required this.children,
    required this.ratios,
  });

  final SplitAxis axis;
  final List<LayoutNode> children;
  final List<double> ratios;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `fvm flutter test test/layout_node_test.dart`
Expected: PASS — 3 tests green.

- [ ] **Step 5: Commit**

```bash
rtk git add lib/layout_node.dart test/layout_node_test.dart
rtk git commit -m "Add the layout tree's types"
```

---

## Task 2: Workspace and splitting

**Files:**
- Create: `lib/workspace.dart`, `test/workspace_test.dart`

**Interfaces:**
- Consumes: everything from Task 1.
- Produces: `class Workspace` with `final LayoutNode root`, `final String focusedId`, a const constructor `Workspace({required LayoutNode root, required String focusedId})`, `factory Workspace.single(String sessionId)`, `List<String> get sessionIds`, `Workspace focus(String sessionId)`, and `Workspace split({required SplitAxis axis, required String newSessionId})`.

- [ ] **Step 1: Write the failing test**

Create `test/workspace_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/layout_node.dart';
import 'package:orthanc/workspace.dart';

void main() {
  group('Workspace.single', () {
    test('holds one pane, focused', () {
      const expectedId = 'a';

      final workspace = Workspace.single(expectedId);

      expect(workspace.root, isA<PaneNode>());
      expect((workspace.root as PaneNode).sessionId, expectedId);
      expect(workspace.focusedId, expectedId);
    });
  });

  group('Workspace.split', () {
    test('wraps a lone pane in a split holding both', () {
      final expected = ['a', 'b'];

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');

      expect(workspace.root, isA<SplitNode>());
      final root = workspace.root as SplitNode;
      expect(root.axis, SplitAxis.row);
      expect(workspace.sessionIds, expected);
    });

    test('focuses the newly created pane', () {
      const expected = 'b';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: expected);

      expect(workspace.focusedId, expected);
    });

    test('inserts as a sibling when the parent runs the same axis', () {
      final expected = ['a', 'c', 'b'];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c');

      expect(workspace.root, isA<SplitNode>());
      expect((workspace.root as SplitNode).children.length, 3);
      expect(workspace.sessionIds, expected);
    });

    test('wraps the focused pane when the parent runs the other axis', () {
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.column, newSessionId: 'c');

      final root = workspace.root as SplitNode;
      expect(root.axis, SplitAxis.row);
      expect(root.children.length, 2);
      expect(root.children.first, isA<SplitNode>());
      expect((root.children.first as SplitNode).axis, SplitAxis.column);
    });

    test('redistributes ratios evenly across the split', () {
      final expected = [1 / 3, 1 / 3, 1 / 3];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c');

      expect((workspace.root as SplitNode).ratios, expected);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/workspace.dart'`.

- [ ] **Step 3: Implement Workspace and split**

Create `lib/workspace.dart`:

```dart
import 'layout_node.dart';

/// The arrangement of panes and which one has focus.
///
/// Immutable: every operation returns a new [Workspace], so a test is three
/// lines with no setup and no teardown. It holds session ids, never sessions,
/// which is why it needs neither a Flutter engine nor a live process.
class Workspace {
  const Workspace({required this.root, required this.focusedId});

  /// The window holding a single session — how the app starts.
  factory Workspace.single(String sessionId) =>
      Workspace(root: PaneNode(sessionId), focusedId: sessionId);

  final LayoutNode root;
  final String focusedId;

  /// Every session in the tree, left to right, top to bottom.
  List<String> get sessionIds => _idsOf(root);

  static List<String> _idsOf(LayoutNode node) => switch (node) {
    PaneNode(:final sessionId) => [sessionId],
    SplitNode(:final children) => [
      for (final child in children) ..._idsOf(child),
    ],
  };

  Workspace focus(String sessionId) =>
      Workspace(root: root, focusedId: sessionId);

  /// Divides the focused pane, putting [newSessionId] beside or below it.
  ///
  /// Two rules, chosen by one comparison — does the focused pane's parent split
  /// already run along [axis]? If it does, the new pane joins that split as the
  /// next sibling and the tree stays flat. If it does not (or the focused pane
  /// is the root), the focused pane is replaced by a new split holding both and
  /// the tree deepens by one level. Either way the new pane ends up adjacent to
  /// the focused one; only the shape differs.
  Workspace split({required SplitAxis axis, required String newSessionId}) {
    final wrapped = _wrapIfFocused(root, axis, newSessionId);
    return Workspace(
      root: wrapped ?? _insertBeside(root, axis, newSessionId),
      focusedId: newSessionId,
    );
  }

  /// Handles the case where the focused pane is the whole tree.
  LayoutNode? _wrapIfFocused(
    LayoutNode node,
    SplitAxis axis,
    String newSessionId,
  ) {
    if (node is PaneNode && node.sessionId == focusedId) {
      return SplitNode(
        axis: axis,
        children: [node, PaneNode(newSessionId)],
        ratios: evenRatios(2),
      );
    }
    return null;
  }

  LayoutNode _insertBeside(
    LayoutNode node,
    SplitAxis axis,
    String newSessionId,
  ) {
    if (node is PaneNode) return node;

    final split = node as SplitNode;
    final at = split.children.indexWhere(
      (child) => child is PaneNode && child.sessionId == focusedId,
    );

    if (at != -1 && split.axis == axis) {
      final children = [...split.children]
        ..insert(at + 1, PaneNode(newSessionId));
      return SplitNode(
        axis: axis,
        children: children,
        ratios: evenRatios(children.length),
      );
    }

    if (at != -1) {
      final children = [...split.children];
      children[at] = SplitNode(
        axis: axis,
        children: [children[at], PaneNode(newSessionId)],
        ratios: evenRatios(2),
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
          _insertBeside(child, axis, newSessionId),
      ],
      ratios: split.ratios,
    );
  }
}

/// [count] equal shares, summing to 1.
List<double> evenRatios(int count) =>
    List<double>.filled(count, 1 / count, growable: false);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — all 6 tests green.

- [ ] **Step 5: Commit**

```bash
rtk git add lib/workspace.dart test/workspace_test.dart
rtk git commit -m "Add Workspace and the two splitting rules"
```

---

## Task 3: Closing a pane, and dissolving what it leaves behind

**Files:**
- Modify: `lib/workspace.dart`, `test/workspace_test.dart`

**Interfaces:**
- Consumes: Task 2's `Workspace`.
- Produces: `Workspace? close(String sessionId)` — returns `null` when the closed pane was the last one, which the app reads as "quit".

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/workspace_test.dart`:

```dart
  group('Workspace.close', () {
    test('returns null when the last pane closes', () {
      const expected = null;

      final actual = Workspace.single('a').close('a');

      expect(actual, expected);
    });

    test('removes the pane and leaves the others', () {
      final expected = ['a', 'c'];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .close('b');

      expect(workspace!.sessionIds, expected);
    });

    test('dissolves a split left holding a single child', () {
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .close('c');

      // 'b' and 'c' shared a column inside the row; removing 'c' must leave
      // 'b' hoisted directly into the row, not wrapped in a one-child split.
      final root = workspace!.root as SplitNode;
      expect(root.children.length, 2);
      expect(root.children[1], isA<PaneNode>());
      expect((root.children[1] as PaneNode).sessionId, 'b');
    });

    test('collapses the tree to a bare pane when one session remains', () {
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .close('b');

      expect(workspace!.root, isA<PaneNode>());
      expect((workspace.root as PaneNode).sessionId, 'a');
    });

    test('moves focus off the closed pane', () {
      const expected = 'a';

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .close('b');

      expect(workspace!.focusedId, expected);
    });

    test('leaves focus alone when another pane closes', () {
      const expected = 'c';

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .close('a');

      expect(workspace!.focusedId, expected);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — `The method 'close' isn't defined for the type 'Workspace'`.

- [ ] **Step 3: Implement close**

Add to `Workspace` in `lib/workspace.dart`, after `split`:

```dart
  /// Removes a pane, returning null when it was the last one.
  ///
  /// Removal runs the splitting rules backwards: take the pane out, and if its
  /// parent split is left holding a single child, dissolve that split and hoist
  /// the child into its place. Without that collapse the tree accumulates
  /// one-child splits that draw nothing yet still hold ratios — invisible on
  /// screen, and how a layout rots over a long session.
  Workspace? close(String sessionId) {
    final remaining = _without(root, sessionId);
    if (remaining == null) return null;

    final ids = _idsOf(remaining);
    return Workspace(
      root: remaining,
      focusedId: ids.contains(focusedId) ? focusedId : ids.first,
    );
  }

  static LayoutNode? _without(LayoutNode node, String sessionId) {
    if (node is PaneNode) {
      return node.sessionId == sessionId ? null : node;
    }

    final split = node as SplitNode;
    final kept = <LayoutNode>[];
    for (final child in split.children) {
      final survivor = _without(child, sessionId);
      if (survivor != null) kept.add(survivor);
    }

    if (kept.isEmpty) return null;
    if (kept.length == 1) return kept.single;
    return SplitNode(
      axis: split.axis,
      children: kept,
      ratios: evenRatios(kept.length),
    );
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — all 12 tests green.

- [ ] **Step 5: Commit**

```bash
rtk git add lib/workspace.dart test/workspace_test.dart
rtk git commit -m "Close a pane and dissolve the split it leaves behind"
```

---

## Task 4: Pane rectangles

**Files:**
- Modify: `lib/workspace.dart`, `test/workspace_test.dart`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: `Map<String, PaneRect> paneRects()` — every pane's share of the window in fractions of the whole. Task 5 uses it to answer directional focus; Task 10 uses the same ratios to lay widgets out.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/workspace_test.dart`:

```dart
  group('Workspace.paneRects', () {
    test('gives a lone pane the whole window', () {
      const expected = PaneRect(left: 0, top: 0, width: 1, height: 1);

      final rects = Workspace.single('a').paneRects();

      expect(rects['a'], expected);
    });

    test('halves the width for a row split', () {
      const expectedLeft = PaneRect(left: 0, top: 0, width: 0.5, height: 1);
      const expectedRight = PaneRect(left: 0.5, top: 0, width: 0.5, height: 1);

      final rects = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').paneRects();

      expect(rects['a'], expectedLeft);
      expect(rects['b'], expectedRight);
    });

    test('halves the height for a column split', () {
      const expectedTop = PaneRect(left: 0, top: 0, width: 1, height: 0.5);
      const expectedBottom = PaneRect(left: 0, top: 0.5, width: 1, height: 0.5);

      final rects = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').paneRects();

      expect(rects['a'], expectedTop);
      expect(rects['b'], expectedBottom);
    });

    test('nests a column inside a row', () {
      const expected = PaneRect(left: 0.5, top: 0.5, width: 0.5, height: 0.5);

      final rects = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .paneRects();

      expect(rects['c'], expected);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — `The method 'paneRects' isn't defined for the type 'Workspace'`.

- [ ] **Step 3: Implement paneRects**

Add to `Workspace` in `lib/workspace.dart`:

```dart
  /// Every pane's share of the window, in fractions of the whole.
  ///
  /// The same numbers the widgets lay out by, which is what lets a directional
  /// focus move be decided here rather than guessed at from the screen.
  Map<String, PaneRect> paneRects() {
    final rects = <String, PaneRect>{};
    _fill(root, const PaneRect(left: 0, top: 0, width: 1, height: 1), rects);
    return rects;
  }

  static void _fill(
    LayoutNode node,
    PaneRect within,
    Map<String, PaneRect> into,
  ) {
    if (node is PaneNode) {
      into[node.sessionId] = within;
      return;
    }

    final split = node as SplitNode;
    var offset = 0.0;
    for (var i = 0; i < split.children.length; i++) {
      final share = split.ratios[i];
      final child = switch (split.axis) {
        SplitAxis.row => PaneRect(
          left: within.left + offset * within.width,
          top: within.top,
          width: within.width * share,
          height: within.height,
        ),
        SplitAxis.column => PaneRect(
          left: within.left,
          top: within.top + offset * within.height,
          width: within.width,
          height: within.height * share,
        ),
      };
      _fill(split.children[i], child, into);
      offset += share;
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — all 16 tests green.

- [ ] **Step 5: Commit**

```bash
rtk git add lib/workspace.dart test/workspace_test.dart
rtk git commit -m "Compute each pane's share of the window"
```

---

## Task 5: Directional focus

**Files:**
- Modify: `lib/workspace.dart`, `test/workspace_test.dart`

**Interfaces:**
- Consumes: Task 4's `paneRects()`.
- Produces: `String? neighbour(Direction direction)` — the id of the nearest pane that way, or null when there is none.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/workspace_test.dart`:

```dart
  group('Workspace.neighbour', () {
    test('finds the pane to the right', () {
      const expected = 'b';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').focus('a');

      expect(workspace.neighbour(Direction.right), expected);
    });

    test('finds the pane to the left', () {
      const expected = 'a';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');

      expect(workspace.neighbour(Direction.left), expected);
    });

    test('finds the pane below', () {
      const expected = 'b';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').focus('a');

      expect(workspace.neighbour(Direction.down), expected);
    });

    test('returns null at the edge', () {
      const expected = null;

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').focus('a');

      expect(workspace.neighbour(Direction.left), expected);
    });

    test('returns null for a lone pane in every direction', () {
      final workspace = Workspace.single('a');

      expect(workspace.neighbour(Direction.left), null);
      expect(workspace.neighbour(Direction.right), null);
      expect(workspace.neighbour(Direction.up), null);
      expect(workspace.neighbour(Direction.down), null);
    });

    test('crosses into a nested split', () {
      const expected = 'b';

      // a | (b over c) — moving right from 'a' meets 'b', the upper of the two.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .focus('a');

      expect(workspace.neighbour(Direction.right), expected);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — `The method 'neighbour' isn't defined for the type 'Workspace'`.

- [ ] **Step 3: Implement neighbour**

Add to `Workspace` in `lib/workspace.dart`:

```dart
  /// The nearest pane in [direction], or null at the edge of the window.
  ///
  /// Decided from the same rectangles the widgets lay out by: keep only panes
  /// genuinely on that side, then take the one whose centre lies closest to the
  /// focused pane's own centre along the perpendicular axis — so moving right
  /// from a tall pane meets whichever neighbour sits level with it.
  String? neighbour(Direction direction) {
    final rects = paneRects();
    final from = rects[focusedId];
    if (from == null) return null;

    String? best;
    var bestOffset = double.infinity;

    for (final entry in rects.entries) {
      if (entry.key == focusedId) continue;
      final to = entry.value;

      final beyond = switch (direction) {
        Direction.left => to.right <= from.left,
        Direction.right => to.left >= from.right,
        Direction.up => to.bottom <= from.top,
        Direction.down => to.top >= from.bottom,
      };
      if (!beyond) continue;

      final offset = switch (direction) {
        Direction.left || Direction.right => (to.centerY - from.centerY).abs(),
        Direction.up || Direction.down => (to.centerX - from.centerX).abs(),
      };
      if (offset < bestOffset) {
        bestOffset = offset;
        best = entry.key;
      }
    }

    return best;
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — all 22 tests green.

- [ ] **Step 5: Commit**

```bash
rtk git add lib/workspace.dart test/workspace_test.dart
rtk git commit -m "Answer directional focus from the pane rectangles"
```

---

## Task 6: Resizing a divider

**Files:**
- Modify: `lib/workspace.dart`, `test/workspace_test.dart`

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: `Workspace resizeSplit({required LayoutNode split, required int dividerIndex, required double delta})` — moves one divider of one split by `delta` (a fraction of that split's extent), taking from one neighbour and giving to the other. Task 10's drag handler calls it.

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/workspace_test.dart`:

```dart
  group('Workspace.resizeSplit', () {
    test('moves share from one side of the divider to the other', () {
      final expected = [0.6, 0.4];

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');
      final resized = workspace.resizeSplit(
        split: workspace.root,
        dividerIndex: 0,
        delta: 0.1,
      );

      expect((resized.root as SplitNode).ratios, expected);
    });

    test('refuses to shrink a pane past a minimum share', () {
      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');
      final resized = workspace.resizeSplit(
        split: workspace.root,
        dividerIndex: 0,
        delta: 0.9,
      );

      final ratios = (resized.root as SplitNode).ratios;
      expect(ratios[1], greaterThanOrEqualTo(minPaneRatio));
      expect(ratios[0] + ratios[1], closeTo(1, 0.0001));
    });

    test('leaves other splits untouched', () {
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c');
      final nested = (workspace.root as SplitNode).children[1];

      final resized = workspace.resizeSplit(
        split: nested,
        dividerIndex: 0,
        delta: 0.1,
      );

      expect((resized.root as SplitNode).ratios, [0.5, 0.5]);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — `The method 'resizeSplit' isn't defined for the type 'Workspace'` and `Undefined name 'minPaneRatio'`.

- [ ] **Step 3: Implement resizeSplit**

Add to `lib/workspace.dart` — the constant beside `evenRatios` at the end of the file, the method inside `Workspace`:

```dart
/// The least share a pane may be dragged down to, so it can never vanish
/// behind its own divider.
const minPaneRatio = 0.05;
```

```dart
  /// Moves one divider of one split, taking share from one side and giving it
  /// to the other. [delta] is a fraction of that split's own extent.
  ///
  /// Identity is by reference: [split] is the node the dragged divider belongs
  /// to, which the widget already holds. Only that node's ratios change.
  Workspace resizeSplit({
    required LayoutNode split,
    required int dividerIndex,
    required double delta,
  }) {
    return Workspace(
      root: _resized(root, split, dividerIndex, delta),
      focusedId: focusedId,
    );
  }

  static LayoutNode _resized(
    LayoutNode node,
    LayoutNode target,
    int dividerIndex,
    double delta,
  ) {
    if (node is PaneNode) return node;

    final split = node as SplitNode;
    if (identical(split, target)) {
      final ratios = [...split.ratios];
      final before = ratios[dividerIndex];
      final after = ratios[dividerIndex + 1];
      final room = before + after;
      final moved = (before + delta).clamp(minPaneRatio, room - minPaneRatio);
      ratios[dividerIndex] = moved;
      ratios[dividerIndex + 1] = room - moved;
      return SplitNode(
        axis: split.axis,
        children: split.children,
        ratios: ratios,
      );
    }

    return SplitNode(
      axis: split.axis,
      children: [
        for (final child in split.children)
          _resized(child, target, dividerIndex, delta),
      ],
      ratios: split.ratios,
    );
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — all 25 tests green.

- [ ] **Step 5: Commit**

```bash
rtk git add lib/workspace.dart test/workspace_test.dart
rtk git commit -m "Move a divider without disturbing the rest of the tree"
```

---

## Task 7: Per-platform hotkeys

**Files:**
- Create: `lib/split_shortcuts.dart`, `test/split_shortcuts_test.dart`

**Interfaces:**
- Consumes: `SplitAxis`, `Direction` from Task 1.
- Produces: `sealed class PaneAction`; `class SplitPane extends PaneAction` with `final SplitAxis axis`; `class ClosePane extends PaneAction`; `class MoveFocus extends PaneAction` with `final Direction direction`; and `PaneAction? paneAction({required bool isWindows, required LogicalKeyboardKey key, required bool isControlPressed, required bool isShiftPressed, required bool isAltPressed, required bool isMetaPressed})`.

- [ ] **Step 1: Write the failing test**

Create `test/split_shortcuts_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/layout_node.dart';
import 'package:orthanc/split_shortcuts.dart';

PaneAction? macAction(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool meta = false,
  bool alt = false,
}) => paneAction(
  isWindows: false,
  key: key,
  isControlPressed: false,
  isShiftPressed: shift,
  isAltPressed: alt,
  isMetaPressed: meta,
);

PaneAction? windowsAction(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool control = false,
  bool alt = false,
}) => paneAction(
  isWindows: true,
  key: key,
  isControlPressed: control,
  isShiftPressed: shift,
  isAltPressed: alt,
  isMetaPressed: false,
);

void main() {
  group('macOS', () {
    test('Cmd+D splits into a row', () {
      const expected = SplitAxis.row;

      final action = macAction(LogicalKeyboardKey.keyD, meta: true);

      expect((action as SplitPane).axis, expected);
    });

    test('Cmd+Shift+D splits into a column', () {
      const expected = SplitAxis.column;

      final action = macAction(
        LogicalKeyboardKey.keyD,
        meta: true,
        shift: true,
      );

      expect((action as SplitPane).axis, expected);
    });

    test('Cmd+W closes the pane', () {
      final action = macAction(LogicalKeyboardKey.keyW, meta: true);

      expect(action, isA<ClosePane>());
    });

    test('Cmd+Opt+Left moves focus left', () {
      const expected = Direction.left;

      final action = macAction(
        LogicalKeyboardKey.arrowLeft,
        meta: true,
        alt: true,
      );

      expect((action as MoveFocus).direction, expected);
    });

    test('a bare D is left for the terminal', () {
      const expected = null;

      final action = macAction(LogicalKeyboardKey.keyD);

      expect(action, expected);
    });
  });

  group('Windows', () {
    test('Alt+Shift+Equal splits into a row', () {
      const expected = SplitAxis.row;

      final action = windowsAction(
        LogicalKeyboardKey.equal,
        alt: true,
        shift: true,
      );

      expect((action as SplitPane).axis, expected);
    });

    test('Alt+Shift+Minus splits into a column', () {
      const expected = SplitAxis.column;

      final action = windowsAction(
        LogicalKeyboardKey.minus,
        alt: true,
        shift: true,
      );

      expect((action as SplitPane).axis, expected);
    });

    test('Ctrl+Shift+W closes the pane', () {
      final action = windowsAction(
        LogicalKeyboardKey.keyW,
        control: true,
        shift: true,
      );

      expect(action, isA<ClosePane>());
    });

    test('Alt+Down moves focus down', () {
      const expected = Direction.down;

      final action = windowsAction(LogicalKeyboardKey.arrowDown, alt: true);

      expect((action as MoveFocus).direction, expected);
    });

    test('Ctrl+D is never bound — it is EOF', () {
      const expected = null;

      final action = windowsAction(LogicalKeyboardKey.keyD, control: true);

      expect(action, expected);
    });
  });

  test('the mac scheme does not fire on Windows', () {
    const expected = null;

    final action = windowsAction(LogicalKeyboardKey.keyD, control: true);

    expect(action, expected);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/split_shortcuts_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/split_shortcuts.dart'`.

- [ ] **Step 3: Implement the shortcuts**

Create `lib/split_shortcuts.dart`:

```dart
import 'package:flutter/services.dart';

import 'layout_node.dart';

/// Something a key press asks of the layout, rather than of the terminal.
sealed class PaneAction {
  const PaneAction();
}

class SplitPane extends PaneAction {
  const SplitPane(this.axis);

  final SplitAxis axis;
}

class ClosePane extends PaneAction {
  const ClosePane();
}

class MoveFocus extends PaneAction {
  const MoveFocus(this.direction);

  final Direction direction;
}

/// What a key press means to the layout, or null to let the terminal have it.
///
/// Each platform wears the scheme of the terminal already in use there — iTerm2
/// on macOS, Windows Terminal on Windows. Ctrl+D is bound on neither: it is
/// EOF, and would kill a session rather than split it. A pure decision with no
/// I/O, in the same shape as shellCommand() and ptyEnvironment().
PaneAction? paneAction({
  required bool isWindows,
  required LogicalKeyboardKey key,
  required bool isControlPressed,
  required bool isShiftPressed,
  required bool isAltPressed,
  required bool isMetaPressed,
}) {
  if (isWindows) {
    if (isAltPressed && isShiftPressed && key == LogicalKeyboardKey.equal) {
      return const SplitPane(SplitAxis.row);
    }
    if (isAltPressed && isShiftPressed && key == LogicalKeyboardKey.minus) {
      return const SplitPane(SplitAxis.column);
    }
    if (isControlPressed && isShiftPressed && key == LogicalKeyboardKey.keyW) {
      return const ClosePane();
    }
    if (isAltPressed && !isShiftPressed) {
      final direction = _arrow(key);
      if (direction != null) return MoveFocus(direction);
    }
    return null;
  }

  if (isMetaPressed && key == LogicalKeyboardKey.keyD) {
    return SplitPane(isShiftPressed ? SplitAxis.column : SplitAxis.row);
  }
  if (isMetaPressed && key == LogicalKeyboardKey.keyW) {
    return const ClosePane();
  }
  if (isMetaPressed && isAltPressed) {
    final direction = _arrow(key);
    if (direction != null) return MoveFocus(direction);
  }
  return null;
}

Direction? _arrow(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.arrowLeft => Direction.left,
  LogicalKeyboardKey.arrowRight => Direction.right,
  LogicalKeyboardKey.arrowUp => Direction.up,
  LogicalKeyboardKey.arrowDown => Direction.down,
  _ => null,
};
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/split_shortcuts_test.dart`
Expected: PASS — all 11 tests green.

- [ ] **Step 5: Commit**

```bash
rtk git add lib/split_shortcuts.dart test/split_shortcuts_test.dart
rtk git commit -m "Read a key press as a pane action, per platform"
```

---

## Task 8: Session

**Files:**
- Create: `lib/session.dart`, `test/session_test.dart`

**Interfaces:**
- Consumes: `ptyEnvironment()` from `lib/pty_environment.dart`.
- Produces: `class Session` with `Session({required this.id, required String executable})`, `final String id`, `final Terminal terminal`, `final ValueNotifier<String> title`, `final ValueNotifier<bool> busy`, `Future<int> get exitCode`, `void start()`, `void dispose()`, and `const busyWindow = Duration(milliseconds: 500)`.

**Note:** the pty wiring below is Milestone 0's, moved rather than rewritten. `_spawn`, `_wire` and the working-directory comment are carried over verbatim from `lib/pty_terminal.dart`; what is new is that a `Session` owns them instead of a widget, plus the title and busy notifiers.

- [ ] **Step 1: Write the failing test**

Create `test/session_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/session.dart';

void main() {
  test('stores the id and executable it is given', () {
    const expectedId = 'a';
    const expectedExecutable = 'cmd.exe';

    final session = Session(id: expectedId, executable: expectedExecutable);

    expect(session.id, expectedId);
    expect(session.executable, expectedExecutable);
  });

  test('starts idle, titled by its executable', () {
    const expectedTitle = 'cmd.exe';
    const expectedBusy = false;

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.title.value, expectedTitle);
    expect(session.busy.value, expectedBusy);
  });

  test('waits half a second before calling a session idle', () {
    const expected = Duration(milliseconds: 500);

    expect(busyWindow, expected);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/session_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/session.dart'`.

- [ ] **Step 3: Implement Session**

Create `lib/session.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'pty_environment.dart';

/// How long a session goes without output before it is called idle.
///
/// There is no busy signal in a pty — nothing in the protocol says a program is
/// working. Output activity fits by accident of how TUIs work: an animating
/// spinner is continuous output, and a prompt waiting for input emits nothing.
/// Too short and the icon flickers between bursts; too long and it lags behind
/// a finished task. Only a running app settles the number.
const busyWindow = Duration(milliseconds: 500);

/// One running program, its terminal, and what the window needs to know of it.
///
/// A session outlives any widget: a pane that moves within the layout must not
/// restart its process. That is why the pty lives here rather than in a State,
/// as it did while the app held exactly one terminal for its whole life.
class Session {
  Session({required this.id, required this.executable});

  final String id;
  final String executable;

  final terminal = Terminal(maxLines: 10000);

  /// The title the running program sets for itself, via OSC 0/2 — the same one
  /// tmux and iTerm show. Claude Code writes its current task there.
  late final ValueNotifier<String> title = ValueNotifier(executable);

  /// Whether output has arrived within [busyWindow].
  final busy = ValueNotifier(false);

  Pty? _pty;
  Timer? _idleTimer;
  final _exited = Completer<int>();

  Future<int> get exitCode => _exited.future;

  void start() {
    if (_pty != null) return;
    final pty = _spawn();
    _pty = pty;
    _wire(pty);
  }

  Pty _spawn() {
    // Without an explicit workingDirectory, Pty.start() defaults to wherever
    // this process's own cwd happens to be — unpredictable for a real
    // double-clicked .app, not just this dev session. Default to $HOME.
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return Pty.start(
      executable,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
      environment: ptyEnvironment(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
      ),
      workingDirectory: home,
    );
  }

  void _wire(Pty pty) {
    pty.output.cast<List<int>>().transform(const Utf8Decoder()).listen((data) {
      terminal.write(data);
      _markBusy();
    });

    pty.exitCode.then((code) {
      terminal.write('the process exited with exit code $code');
      _idleTimer?.cancel();
      busy.value = false;
      if (!_exited.isCompleted) _exited.complete(code);
    });

    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (w, h, pw, ph) {
      pty.resize(h, w);
    };

    terminal.onTitleChange = (value) {
      if (value.isNotEmpty) title.value = value;
    };
  }

  void _markBusy() {
    busy.value = true;
    _idleTimer?.cancel();
    _idleTimer = Timer(busyWindow, () => busy.value = false);
  }

  void dispose() {
    _idleTimer?.cancel();
    _pty?.kill();
    title.dispose();
    busy.dispose();
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/session_test.dart`
Expected: PASS — 3 tests green. (Construction alone touches no pty; `start()` is what spawns, and no test calls it.)

- [ ] **Step 5: Commit**

```bash
rtk git add lib/session.dart test/session_test.dart
rtk git commit -m "Give a session its own life, apart from any widget"
```

---

## Task 9: The sessions registry, the pane bar, and the pane

**Files:**
- Create: `lib/sessions.dart`, `lib/pane_bar.dart`, `lib/pane_view.dart`, `test/sessions_test.dart`
- Delete: `lib/pty_terminal.dart`, `test/pty_terminal_test.dart`

**Interfaces:**
- Consumes: `Session` from Task 8, `shellCommand()` from `lib/shell_command.dart`.
- Produces: `class Sessions` with `Session spawn()`, `Session? operator [](String id)`, `void remove(String id)`, `void disposeAll()`; `class PaneBar extends StatelessWidget` taking `{required Session session, required bool focused}`; `class PaneView extends StatelessWidget` taking `{required Session session, required bool focused, required VoidCallback onFocus}`.

**Note:** `PtyTerminal` is deleted here, not deprecated. Its spawn/wire logic now lives in `Session` (Task 8) and its `TerminalView` in `PaneView`. Its test went with it — that test only ever covered a constructor whose widget no longer exists.

- [ ] **Step 1: Write the failing test**

Create `test/sessions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/sessions.dart';

void main() {
  test('gives each session a distinct id', () {
    final sessions = Sessions();

    final first = sessions.spawn();
    final second = sessions.spawn();

    expect(first.id, isNot(second.id));
  });

  test('finds a session by its id', () {
    final sessions = Sessions();

    final session = sessions.spawn();

    expect(sessions[session.id], same(session));
  });

  test('forgets a removed session', () {
    const expected = null;
    final sessions = Sessions();
    final session = sessions.spawn();

    sessions.remove(session.id);

    expect(sessions[session.id], expected);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/sessions_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/sessions.dart'`.

- [ ] **Step 3: Implement Sessions**

Create `lib/sessions.dart`:

```dart
import 'dart:io';

import 'session.dart';
import 'shell_command.dart';

/// The living sessions, by id.
///
/// The layout tree owns the arrangement; this owns the things arranged. Neither
/// knows about the other, which is what keeps the tree testable.
class Sessions {
  final _byId = <String, Session>{};
  var _next = 0;

  /// Starts a session running the same shell every pane runs.
  ///
  /// One command for every pane is deliberate: choosing a command per pane is
  /// deferred, and the user starts `claude` by hand inside the shell, exactly
  /// as they do today.
  Session spawn() {
    final session = Session(
      id: '${_next++}',
      executable: shellCommand(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
      ),
    );
    _byId[session.id] = session;
    return session;
  }

  Session? operator [](String id) => _byId[id];

  void remove(String id) {
    _byId.remove(id)?.dispose();
  }

  void disposeAll() {
    for (final session in _byId.values) {
      session.dispose();
    }
    _byId.clear();
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/sessions_test.dart`
Expected: PASS — 3 tests green. (`spawn()` constructs a `Session` but never calls `start()`, so no process is created.)

- [ ] **Step 5: Implement the pane bar**

Create `lib/pane_bar.dart`:

```dart
import 'package:flutter/material.dart';

import 'session.dart';

/// The thin strip naming a pane.
///
/// With no tab strip to carry a name, each pane names itself — and that is all
/// this bar does. The leading slot holds a spinner only while the session is
/// working, and collapses entirely when it is not, so the glyph always means
/// the one thing: work is happening now.
class PaneBar extends StatelessWidget {
  const PaneBar({super.key, required this.session, required this.focused});

  static const height = 22.0;

  final Session session;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: focused ? scheme.surfaceContainerHighest : scheme.surfaceContainer,
      child: Row(
        children: [
          ValueListenableBuilder(
            valueListenable: session.busy,
            builder: (context, busy, child) => busy
                ? const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: session.title,
              builder: (context, title, child) => Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: focused ? FontWeight.w700 : FontWeight.w400,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Implement the pane**

Create `lib/pane_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'pane_bar.dart';
import 'session.dart';

/// One pane: its bar, and the terminal beneath.
///
/// The terminal is handed a session rather than spawning one — moving a pane
/// within the layout must not restart its process.
class PaneView extends StatelessWidget {
  const PaneView({
    super.key,
    required this.session,
    required this.focused,
    required this.onFocus,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onFocus(),
      child: Column(
        children: [
          PaneBar(session: session, focused: focused),
          Expanded(
            child: TerminalView(session.terminal, autofocus: focused),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Delete the widget these replace**

```bash
rtk git rm lib/pty_terminal.dart test/pty_terminal_test.dart
```

- [ ] **Step 8: Run the whole suite**

Run: `fvm flutter test`
Expected: FAIL — `lib/main.dart` still imports the deleted `pty_terminal.dart`. That is Task 11's work; leave it failing and commit the parts that stand.

- [ ] **Step 9: Commit**

```bash
rtk git add lib/sessions.dart lib/pane_bar.dart lib/pane_view.dart test/sessions_test.dart
rtk git commit -m "Replace PtyTerminal with a session registry, a bar, and a pane"
```

---

## Task 10: Rendering the tree

**Files:**
- Create: `lib/split_view.dart`

**Interfaces:**
- Consumes: `LayoutNode` (Task 1), `Workspace.resizeSplit` (Task 6), `PaneView` (Task 9), `Sessions` (Task 9).
- Produces: `class SplitView extends StatelessWidget` taking `{required LayoutNode node, required Sessions sessions, required String focusedId, required void Function(String id) onFocus, required void Function(LayoutNode split, int dividerIndex, double delta) onResize}`.

- [ ] **Step 1: Implement the recursive view**

Create `lib/split_view.dart`:

```dart
import 'package:flutter/material.dart';

import 'layout_node.dart';
import 'pane_view.dart';
import 'sessions.dart';

/// Draws a layout node, recursing into splits.
///
/// This walks the tree and nothing more — every decision about shape was made
/// in [Workspace], where it can be tested. A divider drag reports a delta and
/// lets the tree decide what it means.
class SplitView extends StatelessWidget {
  const SplitView({
    super.key,
    required this.node,
    required this.sessions,
    required this.focusedId,
    required this.onFocus,
    required this.onResize,
  });

  static const dividerThickness = 4.0;

  final LayoutNode node;
  final Sessions sessions;
  final String focusedId;
  final void Function(String id) onFocus;
  final void Function(LayoutNode split, int dividerIndex, double delta)
  onResize;

  @override
  Widget build(BuildContext context) {
    return switch (node) {
      PaneNode(:final sessionId) => _pane(sessionId),
      SplitNode() => _split(node as SplitNode),
    };
  }

  Widget _pane(String sessionId) {
    final session = sessions[sessionId];
    if (session == null) return const SizedBox.shrink();
    return PaneView(
      session: session,
      focused: sessionId == focusedId,
      onFocus: () => onFocus(sessionId),
    );
  }

  Widget _split(SplitNode split) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = split.axis == SplitAxis.row;
        final extent = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final dividers = split.children.length - 1;
        final free = extent - dividers * dividerThickness;

        final children = <Widget>[];
        for (var i = 0; i < split.children.length; i++) {
          if (i > 0) {
            children.add(_divider(context, split, i - 1, horizontal, free));
          }
          children.add(
            SizedBox(
              width: horizontal ? free * split.ratios[i] : null,
              height: horizontal ? null : free * split.ratios[i],
              child: SplitView(
                node: split.children[i],
                sessions: sessions,
                focusedId: focusedId,
                onFocus: onFocus,
                onResize: onResize,
              ),
            ),
          );
        }

        return horizontal
            ? Row(children: children)
            : Column(children: children);
      },
    );
  }

  Widget _divider(
    BuildContext context,
    SplitNode split,
    int index,
    bool horizontal,
    double free,
  ) {
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: horizontal
            ? (details) => onResize(split, index, details.delta.dx / free)
            : null,
        onVerticalDragUpdate: horizontal
            ? null
            : (details) => onResize(split, index, details.delta.dy / free),
        child: SizedBox(
          width: horizontal ? dividerThickness : null,
          height: horizontal ? null : dividerThickness,
          child: ColoredBox(color: Theme.of(context).dividerColor),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `fvm flutter analyze`
Expected: one remaining error — `lib/main.dart` still imports the deleted `pty_terminal.dart`. That is Task 11's work; nothing in `split_view.dart` itself should be flagged.

- [ ] **Step 3: Commit**

```bash
rtk git add lib/split_view.dart
rtk git commit -m "Draw the layout tree, dividers and all"
```

---

## Task 11: Wiring it together

**Files:**
- Create: `lib/workspace_view.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: `class WorkspaceView extends StatefulWidget` with `const WorkspaceView({super.key})`, hosted by `OrthancApp`.

- [ ] **Step 1: Implement the workspace view**

Create `lib/workspace_view.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'layout_node.dart';
import 'session.dart';
import 'sessions.dart';
import 'split_shortcuts.dart';
import 'split_view.dart';
import 'workspace.dart';

/// The window: the sessions, their arrangement, and the keys that change it.
class WorkspaceView extends StatefulWidget {
  const WorkspaceView({super.key});

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  final sessions = Sessions();
  late Workspace workspace;

  @override
  void initState() {
    super.initState();
    // First run opens one session — there is no empty state to design.
    final first = _open();
    workspace = Workspace.single(first.id);
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (mounted) first.start();
    });
  }

  Session _open() {
    final session = sessions.spawn();
    session.exitCode.then((_) {
      if (mounted) _close(session.id);
    });
    return session;
  }

  /// A finished session closes its own pane; the last one quits the app,
  /// carrying the shell's exit code out as it did when the window held one.
  void _close(String id) {
    final next = workspace.close(id);
    if (next == null) {
      sessions.disposeAll();
      exit(0);
    }
    sessions.remove(id);
    setState(() => workspace = next);
  }

  void _split(SplitAxis axis) {
    final session = _open();
    setState(() {
      workspace = workspace.split(axis: axis, newSessionId: session.id);
    });
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (mounted) session.start();
    });
  }

  void _moveFocus(Direction direction) {
    final target = workspace.neighbour(direction);
    if (target == null) return;
    setState(() => workspace = workspace.focus(target));
  }

  /// Steals a key before the terminal can have it, or lets it through.
  ///
  /// In a terminal app every keystroke belongs to the terminal, so a binding
  /// that is not taken here lands in the running program's prompt instead.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final keys = HardwareKeyboard.instance;
    final action = paneAction(
      isWindows: Platform.isWindows,
      key: event.logicalKey,
      isControlPressed: keys.isControlPressed,
      isShiftPressed: keys.isShiftPressed,
      isAltPressed: keys.isAltPressed,
      isMetaPressed: keys.isMetaPressed,
    );
    if (action == null) return KeyEventResult.ignored;

    switch (action) {
      case SplitPane(:final axis):
        _split(axis);
      case ClosePane():
        _close(workspace.focusedId);
      case MoveFocus(:final direction):
        _moveFocus(direction);
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    sessions.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKey,
      child: SplitView(
        node: workspace.root,
        sessions: sessions,
        focusedId: workspace.focusedId,
        onFocus: (id) => setState(() => workspace = workspace.focus(id)),
        onResize: (split, index, delta) => setState(() {
          workspace = workspace.resizeSplit(
            split: split,
            dividerIndex: index,
            delta: delta,
          );
        }),
      ),
    );
  }
}
```

- [ ] **Step 2: Point main.dart at it**

Replace `lib/main.dart` entirely:

```dart
import 'package:flutter/material.dart';

import 'workspace_view.dart';

void main() {
  runApp(const OrthancApp());
}

class OrthancApp extends StatelessWidget {
  const OrthancApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Orthanc',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: SafeArea(child: WorkspaceView())),
    );
  }
}
```

- [ ] **Step 3: Analyze and run the suite**

Run: `fvm flutter analyze && fvm flutter test`
Expected: analyze clean; all tests green — `layout_node` 3, `workspace` 25, `split_shortcuts` 11, `session` 3, `sessions` 3, `claude_command` 4, `shell_command` 3, `pty_environment` 4. The `pty_terminal` tests are gone with the widget.

- [ ] **Step 4: Commit**

```bash
rtk git add lib/workspace_view.dart lib/main.dart
rtk git commit -m "Wire sessions, layout and hotkeys into one window"
```

---

## Task 12: Cross-platform pass

**Files:** none in advance. Any fix lands in whichever file the fault is actually in, decided once observed — not guessed at here.

**Interfaces:**
- Consumes: the whole app.
- Produces: Milestone 1's definition of done.

- [ ] **Step 1: Run on Windows**

```powershell
fvm flutter run -d windows
```

Walk every line, and record what happens rather than what should:

- A single terminal opens, renders, and takes input.
- `Alt+Shift+Plus` splits vertically, the new pane appearing to the **right**.
- `Alt+Shift+Minus` splits horizontally, the new pane appearing **below**.
- Splitting a third time inserts a sibling when the axis matches, and nests when it does not — compare against the tree the spec draws.
- `Alt+arrows` moves focus; the focused pane's bar darkens.
- Clicking a pane focuses it.
- Dividers drag, and a pane cannot be dragged away to nothing.
- Each bar shows its program's own title; run `claude` in one pane and confirm the title follows its task.
- The spinner appears while a pane works and disappears when it settles. **Judge the 500ms window here** — flickering means too short, lag means too long.
- `Ctrl+Shift+W` closes a pane; siblings reflow; the last pane closing quits the app.
- Typing `exit` in a pane does the same as closing it.
- **No hotkey leaks into the terminal** — after each binding, confirm no stray character landed in the prompt.

- [ ] **Step 2: Run on macOS**

```bash
fvm flutter run -d macos
```

The same walk, with `Cmd+D`, `Cmd+Shift+D`, `Cmd+W` and `Cmd+Opt+arrows`.

- [ ] **Step 3: Fix what the walk found**

Fix in the file the fault is in, then repeat the walk on both platforms until it passes clean. If a tree operation proves awkward, mend the tree and its tests — do not move layout logic into a widget, which is how the testable line rises again.

- [ ] **Step 4: Update the records and commit**

Mark this plan's tasks complete, update `README.md`'s status section to describe the split-pane window, and commit:

```bash
rtk git add -A
rtk git commit -m "Confirm Milestone 1 on macOS and Windows"
```

---

## Self-Review

**Spec coverage.** Each of the spec's eleven decisions maps to a task: 1 and 2 → Tasks 1-2 (tree, splitting); 3 → Task 2's insertion rules; 4 → Task 7 (hotkeys, `Ctrl+D` explicitly tested as unbound); 5 and 6 → Task 9's `PaneBar` and Task 8's `onTitleChange`; 7 and 8 → Task 8's `busy` notifier and `busyWindow`; 9 → Task 11's `initState` and `Sessions.spawn()`; 10 → Task 11's `_close`; 11 → Task 6 (resize) and Task 5 (neighbour). The architecture's four units are Tasks 1-2 (`LayoutNode`, `Workspace`), 8 (`Session`), 9 (`Sessions`). The insertion rule's dissolve-on-close is Task 3, with its own test. Keyboard interception is Task 11's `_onKey`. The testing table is realized: `Workspace` and `paneAction` carry 36 unit tests between them; `Session` and `Sessions` are constructor-only; the views are covered by Task 12's manual walk.

**Placeholder scan.** No TBD or TODO; every code step shows the actual code. Task 12 is verification-shaped because the spec frames cross-platform behaviour as discovery, not as a known bug to pre-write a patch for. One rough edge was found in review and fixed rather than disclosed: `_divider` needed a `BuildContext` for `Theme.of` and had none, so an implementer following Task 10 verbatim would have hit a compile error. The signature and its call site now agree.

**Type consistency.** `SplitAxis` and `Direction` are defined once (Task 1) and used unchanged in Tasks 2, 5, 7, 10, 11. `Workspace.split({axis, newSessionId})`, `close(String)`, `focus(String)`, `paneRects()`, `neighbour(Direction)` and `resizeSplit({split, dividerIndex, delta})` keep one signature each across definition, tests and call sites. `PaneAction`'s three subclasses are constructed in Task 7 and destructured in Task 11's switch under the same names. `Session.start()`, `.dispose()`, `.title`, `.busy`, `.exitCode` are defined in Task 8 and called in Tasks 9 and 11 exactly so. `Sessions.spawn()`, `[]`, `remove()`, `disposeAll()` likewise.

**One knowing gap.** `Workspace.resizeSplit` identifies its target node by `identical()`, which holds because `SplitView` passes the very `SplitNode` instance it drew. If a later change rebuilds the tree between draw and drag, that identity breaks — and it would fail silently, the drag simply doing nothing. Task 12's divider check is what catches it.

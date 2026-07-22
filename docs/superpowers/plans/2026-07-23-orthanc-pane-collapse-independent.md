# Pane Collapse — Independent Per-Pane State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Revise the just-shipped pane-collapse feature so each pane in a column tracks its own collapse state independently, rather than a column having one mutually-exclusive "which row is expanded" choice.

**Architecture:** `Workspace.collapsedIds` keeps its name and type (`Set<String>`) but its meaning simplifies: membership now means "this pane, on its own, is collapsed" — no more per-column exclusivity bookkeeping. `toggleCollapse`/`reveal` shrink to plain set operations. `SplitView` replaces "find the one expanded child" with "does this column have any collapsed child at all," and when it does, every collapsed direct pane child shrinks to bar height while everything else (expanded panes, and any nested-split child, which is never itself collapsible) shares the reclaimed space evenly — no ratios, no dividers. `PaneView` drops its separate `shrunk` flag, since `collapsed` now means the same thing for both "hide the terminal" and "show the restore icon."

**Tech Stack:** Flutter/Dart, `flutter_test` for unit tests (no widget-test harness in this codebase — see Global Constraints).

## Context for whoever picks this up

This revises the pane-collapse feature merged to `master` in commit range `94ab0b6..d7ce68e` (design spec: `docs/superpowers/specs/2026-07-23-orthanc-pane-collapse-design.md`; original plan: `docs/superpowers/plans/2026-07-23-orthanc-pane-collapse.md`). That version modeled collapse as **one shared choice per column** — collapsing pane B in a column automatically un-collapsed whichever pane, if any, was collapsed before it, and space was split strictly 1-expanded-vs-rest-shrunk. Manual testing on the running app surfaced a better model: **each pane's collapse state is independent**. Collapsing B has no effect on A's state; a column can have 0, 1, or all of its panes collapsed at once, and however many are expanded simply share the space evenly.

## Global Constraints

- **`lib/workspace_view.dart` and `lib/pane_bar.dart` need NO changes in this plan.** Every call site in `workspace_view.dart` (`_toggleCollapse`, `_moveFocus`, `_dispatch`, the `SplitView(...)` construction in `build()`) already calls the exact same API shapes this plan preserves — only the *internal* semantics of `Workspace.toggleCollapse`/`reveal` and `SplitView`'s column-rendering change, not their signatures. `PaneBar`'s `collapsed ? '⤡' : '⤢'` icon logic already reads correctly per-pane and needs no edit. If you find yourself wanting to touch either file, stop — that's a sign something in this plan was misread.
- Follow the codebase's existing testing split exactly: `Workspace` is unit-tested with no engine (`test/workspace_test.dart`'s existing style: `group`/`test`, a named `expected` constant declared before the call, one assertion against it). `SplitView`/`PaneView` have no automated test harness in this project — verified by eye, running the app, on both platforms (Task 3).
- Every `Workspace` operation stays immutable — return a new `Workspace`, never mutate `this`.
- A column can end up with every pane collapsed (all bars, no terminal bodies) — this is a valid, allowed state, not an edge case to guard against.

---

### Task 1: `Workspace` — independent per-pane collapse state

**Files:**
- Modify: `lib/workspace.dart`
- Modify: `test/workspace_test.dart`

**Interfaces:**
- Produces: `Workspace.toggleCollapse(String) -> Workspace` and `Workspace.reveal(String) -> Workspace` with revised (simpler) semantics — same signatures as today, so nothing outside this file needs to change. `Workspace.collapsibleIds` and `Workspace.collapsedIds` keep their existing type and are unchanged in this task except for what populates them.

- [ ] **Step 1: Replace the stale test groups**

Three groups in `test/workspace_test.dart` test behavior that either changes meaning or stops existing under the new model. Replace them as follows.

Replace the entire `group('Workspace.toggleCollapse', () { ... });` block (currently starting around the line reading `group('Workspace.toggleCollapse', () {` and ending at its matching `});`) with:

```dart
  group('Workspace.toggleCollapse', () {
    test('collapses a pane whose direct parent is a 2-row column', () {
      final expected = {'b'};

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').toggleCollapse('b');

      expect(workspace.collapsedIds, expected);
    });

    test('toggling the same pane twice un-collapses it', () {
      final expected = <String>{};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b')
          .toggleCollapse('b');

      expect(workspace.collapsedIds, expected);
    });

    test(
      'collapsing a different sibling collapses both independently',
      () {
        final expected = {'b', 'c'};

        final workspace = Workspace.single('a')
            .split(axis: SplitAxis.column, newSessionId: 'b')
            .split(axis: SplitAxis.column, newSessionId: 'c')
            .toggleCollapse('b')
            .toggleCollapse('c');

        expect(workspace.collapsedIds, expected);
      },
    );

    test('collapsing every pane in a column is allowed', () {
      final expected = {'a', 'b'};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('a')
          .toggleCollapse('b');

      expect(workspace.collapsedIds, expected);
    });

    test('focuses the pane it collapses', () {
      const expected = 'b';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').toggleCollapse('b');

      expect(workspace.focusedId, expected);
    });

    test('no-ops on a pane inside a row split (side by side)', () {
      final expected = <String>{};

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').toggleCollapse('b');

      expect(workspace.collapsedIds, expected);
    });

    test('no-ops on a lone pane with no split at all', () {
      final expected = <String>{};

      final workspace = Workspace.single('a').toggleCollapse('a');

      expect(workspace.collapsedIds, expected);
    });

    test('two different columns collapse independently', () {
      final expected = {'b', 'd'};

      // (a over b) | (c over d) — a row split holding two columns.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .split(axis: SplitAxis.column, newSessionId: 'd')
          .toggleCollapse('b')
          .toggleCollapse('d');

      expect(workspace.collapsedIds, expected);
    });
  });
```

Replace the entire `group('Workspace.reveal', () { ... });` block with:

```dart
  group('Workspace.reveal', () {
    test('removes the target from collapsedIds when it is collapsed', () {
      final expected = <String>{};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b')
          .reveal('b');

      expect(workspace.collapsedIds, expected);
    });

    test('is a no-op when the target is not collapsed', () {
      final expected = <String>{};

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').reveal('b');

      expect(workspace.collapsedIds, expected);
    });

    test('leaves every other collapsed pane untouched', () {
      final expected = {'c'};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .toggleCollapse('b')
          .toggleCollapse('c')
          .reveal('b');

      expect(workspace.collapsedIds, expected);
    });
  });
```

Delete the entire `group('Workspace.split clearing collapse', () { ... });` block outright — both its tests. That group tested `split()` clearing a collapse entry to reveal a newly-created pane; under the new model `split()` no longer touches `collapsedIds` at all (a brand-new session id can never already be a member of `collapsedIds`, so there is nothing left to clear — see Step 3). Do not replace it with anything; the behavior it tested no longer exists.

Leave `group('Workspace.collapsibleIds', ...)` and the two collapse-related tests inside `group('Workspace.close', ...)` (`'clears its own column\'s collapse entry when the collapsed pane closes'` and `'leaves an unrelated column\'s collapse entry alone'`) exactly as they are — both still pass unchanged under the new model.

- [ ] **Step 2: Run the tests to verify the expected failures**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — the new/changed assertions in `toggleCollapse` and `reveal` fail against the current (pre-this-task) implementation, which still has per-column exclusivity. Specifically `'collapsing a different sibling collapses both independently'` should fail with `collapsedIds` containing only `{'c'}` instead of the expected `{'b', 'c'}`.

- [ ] **Step 3: Implement the simplified `toggleCollapse`, `reveal`, and `split`**

In `lib/workspace.dart`, replace the existing `toggleCollapse` method with:

```dart
  /// Collapses [sessionId] to bar height, independent of every other pane
  /// in its column — or un-collapses it, if it was already collapsed.
  /// No-ops when [sessionId]'s direct parent isn't a column split with 2+
  /// children — the one gate every caller (a bar click, a hotkey) gets for
  /// free by going through here.
  Workspace toggleCollapse(String sessionId) {
    final parent = _directParent(root, sessionId);
    if (parent == null ||
        parent.axis != SplitAxis.column ||
        parent.children.length < 2) {
      return this;
    }

    final updated = {...collapsedIds};
    if (!updated.remove(sessionId)) updated.add(sessionId);

    return Workspace(root: root, focusedId: sessionId, collapsedIds: updated);
  }
```

Replace the existing `reveal` method with:

```dart
  /// Un-collapses [sessionId] if it is currently collapsed. A no-op
  /// otherwise.
  Workspace reveal(String sessionId) {
    if (!collapsedIds.contains(sessionId)) return this;
    return Workspace(
      root: root,
      focusedId: focusedId,
      collapsedIds: {...collapsedIds}..remove(sessionId),
    );
  }
```

Replace the existing `split` method — remove the trailing `.reveal(newSessionId)` call, since a freshly-created session id can never already be a member of `collapsedIds`, making that call provably always a no-op:

```dart
  Workspace split({required SplitAxis axis, required String newSessionId}) {
    final wrapped = _wrapIfFocused(root, axis, newSessionId);
    return Workspace(
      root: wrapped ?? _insertBeside(root, axis, newSessionId),
      focusedId: newSessionId,
      collapsedIds: collapsedIds,
    );
  }
```

Leave `close`, `resizeSplit`, `focus`, `collapsibleIds`, `_collectCollapsible`, `_paneChildIds`, and `_directParent` exactly as they are — none of them need to change. `_paneChildIds` is still used by `_collectCollapsible`; `_directParent` is still used by `toggleCollapse`'s gate check.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — every test in the file.

- [ ] **Step 5: Run the full suite**

Run: `fvm flutter test`
Expected: PASS — no regressions elsewhere (this task touches only `lib/workspace.dart`, consumed by `lib/workspace_view.dart` and `lib/split_view.dart`, neither of which is modified in this task, so nothing else should be affected).

- [ ] **Step 6: Commit**

```bash
git add lib/workspace.dart test/workspace_test.dart
git commit -m "Make pane collapse state independent per pane, not per column"
```

---

### Task 2: `SplitView` and `PaneView` — even-split rendering for independently-collapsed panes

**Files:**
- Modify: `lib/split_view.dart`
- Modify: `lib/pane_view.dart`

**Why one task:** `PaneView` drops its `shrunk` parameter (folded into `collapsed`, which now means the same thing). `SplitView` is `PaneView`'s only caller. Removing a required parameter from `PaneView` and updating its one call site are two halves of one compiling change — there's no point between them where the app builds.

**Interfaces:**
- Consumes: `Workspace.collapsedIds` / `collapsibleIds` (Task 1 — unchanged types, just simpler internal production of `collapsedIds`'s contents).
- Produces: nothing new — `SplitView`'s own constructor and `lib/workspace_view.dart`'s call to it are both unchanged (see Global Constraints). This task only changes what happens *inside* `SplitView` and `PaneView`.

No automated test exists for this layer (see Global Constraints) — verified by eye in Task 3's manual pass. `fvm flutter test`/`fvm flutter analyze` passing clean is the bar for this task.

- [ ] **Step 1: Replace `lib/pane_view.dart`, dropping `shrunk`**

Replace the full contents of `lib/pane_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'pane_bar.dart';
import 'session.dart';

/// One pane: its bar, and the terminal beneath — unless [collapsed], in
/// which case only the bar renders, at its own fixed height, and the
/// terminal is skipped entirely. A pane's [Session] outlives this widget
/// either way.
class PaneView extends StatelessWidget {
  const PaneView({
    super.key,
    required this.session,
    required this.focused,
    required this.onFocus,
    required this.onKeyEvent,
    required this.canCollapse,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;
  final FocusOnKeyEventCallback onKeyEvent;
  final bool canCollapse;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    // Listener sees every pointer down regardless of the gesture arena; a
    // GestureDetector here would compete with xterm's own tap recognizer and
    // routinely lose it on a brisk click.
    return Listener(
      onPointerDown: (_) => onFocus(),
      child: Column(
        children: [
          GestureDetector(
            onTap: canCollapse ? onToggleCollapse : null,
            child: PaneBar(
              session: session,
              focused: focused,
              canCollapse: canCollapse,
              collapsed: collapsed,
            ),
          ),
          if (!collapsed)
            Expanded(
              // xterm's RenderTerminal never clips its own paint, so a scroll
              // can draw rows past its box and into PaneBar above it. Clip
              // explicitly rather than rely on that render object doing it.
              child: ClipRect(
                child: TerminalView(
                  session.terminal,
                  focusNode: session.focusNode,
                  onKeyEvent: onKeyEvent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Replace `lib/split_view.dart`**

Replace the full contents of `lib/split_view.dart`:

```dart
import 'package:flutter/material.dart';

import 'layout_node.dart';
import 'pane_bar.dart';
import 'pane_view.dart';
import 'sessions.dart';

/// Draws a layout node, recursing into splits.
///
/// This walks the tree and nothing more — every decision about shape was
/// made in [Workspace], where it can be tested. A divider drag reports a
/// delta and lets the tree decide what it means. Each pane's collapse
/// state is independent: a column with at least one direct pane child in
/// [collapsedIds] shrinks every collapsed child to bar height and splits
/// the reclaimed space evenly among whatever remains expanded — see
/// [_buildCollapsedSplitChildren]. A column with nothing collapsed renders
/// by its stored ratios exactly as before, dividers and all.
class SplitView extends StatelessWidget {
  const SplitView({
    super.key,
    required this.node,
    required this.sessions,
    required this.focusedId,
    required this.collapsedIds,
    required this.collapsibleIds,
    required this.onFocus,
    required this.onResize,
    required this.onToggleCollapse,
    required this.onKeyEvent,
  });

  static const dividerThickness = 4.0;

  final LayoutNode node;
  final Sessions sessions;
  final String focusedId;
  final Set<String> collapsedIds;
  final Set<String> collapsibleIds;
  final void Function(String id) onFocus;
  final void Function(LayoutNode split, int dividerIndex, double delta)
  onResize;
  final void Function(String id) onToggleCollapse;
  final FocusOnKeyEventCallback onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return switch (node) {
      PaneNode(:final sessionId) => _pane(sessionId),
      SplitNode split => _split(split),
    };
  }

  Widget _pane(String sessionId) => _shrinkablePane(sessionId);

  Widget _shrinkablePane(String sessionId) {
    final session = sessions[sessionId];
    if (session == null) return const SizedBox.shrink();
    return PaneView(
      session: session,
      focused: sessionId == focusedId,
      onFocus: () => onFocus(sessionId),
      onKeyEvent: onKeyEvent,
      canCollapse: collapsibleIds.contains(sessionId),
      collapsed: collapsedIds.contains(sessionId),
      onToggleCollapse: () => onToggleCollapse(sessionId),
    );
  }

  /// Whether any direct pane child of [split] is currently collapsed —
  /// always false whenever [split] isn't a column at all.
  bool _hasCollapsedChild(SplitNode split) {
    if (split.axis != SplitAxis.column) return false;
    return split.children.any(
      (child) => child is PaneNode && collapsedIds.contains(child.sessionId),
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

        final children = _hasCollapsedChild(split)
            ? _buildCollapsedSplitChildren(split, free)
            : _buildRatioSplitChildren(split, context, horizontal, free);

        return horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
      },
    );
  }

  List<Widget> _buildRatioSplitChildren(
    SplitNode split,
    BuildContext context,
    bool horizontal,
    double free,
  ) {
    final children = <Widget>[];
    for (var i = 0; i < split.children.length; i++) {
      if (i > 0) {
        children.add(_divider(context, split, i - 1, horizontal, free));
      }
      children.add(_buildRatioSplitChild(split, i, horizontal, free));
    }
    return children;
  }

  Widget _buildRatioSplitChild(
    SplitNode split,
    int index,
    bool horizontal,
    double free,
  ) {
    return SizedBox(
      width: horizontal ? free * split.ratios[index] : null,
      height: horizontal ? null : free * split.ratios[index],
      child: _childSplitView(split.children[index]),
    );
  }

  /// Sizes a column with at least one collapsed pane: every collapsed
  /// direct pane child shrinks to [PaneBar.height]; everything else — an
  /// expanded pane, or a nested split child, which is never itself
  /// collapsible — shares the reclaimed space evenly. Ratios are ignored
  /// entirely in this state. Only ever called for a column split, so
  /// height is the only dimension that matters here — no [horizontal]
  /// branch needed. No dividers: a fixed-height collapsed row isn't
  /// draggable, and an evenly-split expanded row isn't either.
  List<Widget> _buildCollapsedSplitChildren(SplitNode split, double free) {
    final collapsedCount = split.children
        .whereType<PaneNode>()
        .where((pane) => collapsedIds.contains(pane.sessionId))
        .length;
    final expandedCount = split.children.length - collapsedCount;
    final fixedTotal = collapsedCount * PaneBar.height;
    final evenSize = expandedCount == 0
        ? 0.0
        : ((free - fixedTotal) / expandedCount).clamp(0.0, free);

    final children = <Widget>[];
    for (final child in split.children) {
      if (child is PaneNode && collapsedIds.contains(child.sessionId)) {
        children.add(
          SizedBox(
            height: PaneBar.height,
            child: _shrinkablePane(child.sessionId),
          ),
        );
      } else if (child is PaneNode) {
        children.add(
          SizedBox(height: evenSize, child: _shrinkablePane(child.sessionId)),
        );
      } else {
        children.add(SizedBox(height: evenSize, child: _childSplitView(child)));
      }
    }
    return children;
  }

  Widget _childSplitView(LayoutNode child) {
    return SplitView(
      node: child,
      sessions: sessions,
      focusedId: focusedId,
      collapsedIds: collapsedIds,
      collapsibleIds: collapsibleIds,
      onFocus: onFocus,
      onResize: onResize,
      onToggleCollapse: onToggleCollapse,
      onKeyEvent: onKeyEvent,
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
      child: _dividerGestureDetector(context, split, index, horizontal, free),
    );
  }

  Widget _dividerGestureDetector(
    BuildContext context,
    SplitNode split,
    int index,
    bool horizontal,
    double free,
  ) {
    return GestureDetector(
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
    );
  }
}
```

- [ ] **Step 3: Run the full test suite**

Run: `fvm flutter test`
Expected: PASS — every unit test in the project (this task touches no test files; the bar is that nothing broke).

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/split_view.dart lib/pane_view.dart
git commit -m "Render independently-collapsed panes: even split among what's expanded"
```

---

### Task 3: Manual verification, both platforms

**Files:** none (verification only).

- [ ] **Step 1: Launch on Windows**

Run: `fvm flutter run -d windows`
Expected: app builds and launches with no console errors.

- [ ] **Step 2: Collapse two panes in the same 3-row column, independently**

Split a column into 3 stacked rows. Click the first row's bar to collapse it. Click the second row's bar to collapse it too.
Expected: both the first and second rows shrink to bar-only, stacked in their original order; the third row alone fills the entire reclaimed space (not split with anything, since it's the only one still expanded).

- [ ] **Step 3: Confirm even split among 2+ expanded panes**

From the state in Step 2, click the second row's bar again to expand it back.
Expected: rows 2 and 3 (both now expanded) split the reclaimed space evenly between them — not by their old drag ratios. Row 1 stays collapsed, unaffected.

- [ ] **Step 4: Confirm collapsing every pane in a column is allowed**

Collapse the remaining expanded row(s) too, so every row in the column is collapsed.
Expected: the column shows nothing but a stack of bars — no terminal body anywhere in that column. The app does not crash or misbehave. Clicking any bar expands it again.

- [ ] **Step 5: Confirm a sibling column is still unaffected**

If a second, side-by-side column exists, confirm nothing about its own rows changed while performing Steps 2–4 in the first column.

- [ ] **Step 6: Confirm the hotkey and focus-follow still work**

Focus a collapsed pane via `Alt+Arrow` (it should expand automatically, per the existing `reveal` wiring) and confirm you can type into it immediately. Press `Shift+Alt+Z` (or `Cmd+Shift+Enter` on macOS) on the focused pane and confirm it toggles that pane's own collapse state, matching a bar click.

- [ ] **Step 7: Repeat Steps 2–6 on macOS**

Run: `fvm flutter run -d macos`
Expected: all of the above hold identically, with `Cmd+Shift+Enter` in place of `Shift+Alt+Z`.

- [ ] **Step 8: Run the full automated suite one last time**

Run: `fvm flutter test`
Expected: PASS — confirms nothing drifted between the last commit and the manual walk.

# Pane Collapse/Expand Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one row of a stacked column shrink its siblings to bar-only strips and take their reclaimed space, toggled by a click on any pane's bar or a hotkey, scoped strictly to that one column.

**Architecture:** `Workspace` gains a `collapsedIds: Set<String>` field and three operations (`toggleCollapse`, `reveal`, plus threading through `close`/`split`/`resizeSplit`/`focus`); the gate ("is this pane's direct parent a column split with 2+ children?") lives entirely inside `toggleCollapse`. `SplitView` renders a column specially only when one of its direct children matches a `collapsedIds` entry — every other direct pane child shrinks to bar height, any nested split child keeps its ordinary share. `PaneBar`/`PaneView` gain the click affordance and the ability to omit the terminal body when shrunk.

**Tech Stack:** Flutter/Dart, `flutter_test` for unit tests (no widget-test harness exists in this codebase — see Global Constraints).

## Global Constraints

- Follow the codebase's existing testing split exactly: `Workspace` and `splitShortcuts()` are unit-tested with no engine (per `test/workspace_test.dart` and `test/split_shortcuts_test.dart`'s existing style); widget-level behavior (`PaneBar`, `PaneView`, `SplitView`) has no test harness in this project and is verified **by eye, running the app, on both platforms** — do not introduce a new widget-testing pattern this codebase doesn't otherwise use.
- Match existing test style exactly: `group`/`test`, a named `expected` (or `expectedX`) constant declared before the call, then one assertion comparing against it — see any existing test in `test/workspace_test.dart` for the pattern.
- Every `Workspace` operation stays immutable — return a new `Workspace`, never mutate `this`.
- `collapsedIds` must be threaded through **every** existing `Workspace(...)` constructor call across the file (`focus`, `split`, `close`, `resizeSplit`) — a call site that forgets it will silently reset collapse state on every unrelated operation.

---

### Task 1: `Workspace.toggleCollapse` and the direct-parent gate

**Files:**
- Modify: `lib/workspace.dart`
- Test: `test/workspace_test.dart`

**Interfaces:**
- Produces: `Workspace.collapsedIds` (`Set<String>`, defaults to `const {}`), `Workspace.toggleCollapse(String sessionId) -> Workspace`, `Workspace.collapsibleIds` (`Set<String>` getter).

- [ ] **Step 1: Write the failing tests**

Add a new group at the end of `test/workspace_test.dart`, just before the file's closing `}`:

```dart
  group('Workspace.toggleCollapse', () {
    test('collapses a pane whose direct parent is a 2-row column', () {
      final expected = {'b'};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b');

      expect(workspace.collapsedIds, expected);
    });

    test('toggling the already-collapsed pane restores even shares', () {
      final expected = <String>{};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b')
          .toggleCollapse('b');

      expect(workspace.collapsedIds, expected);
    });

    test('collapsing a different sibling replaces the column\'s entry', () {
      final expected = {'c'};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .toggleCollapse('b')
          .toggleCollapse('c');

      expect(workspace.collapsedIds, expected);
    });

    test('focuses the pane it collapses', () {
      const expected = 'b';

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b');

      expect(workspace.focusedId, expected);
    });

    test('no-ops on a pane inside a row split (side by side)', () {
      final expected = <String>{};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .toggleCollapse('b');

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

  group('Workspace.collapsibleIds', () {
    test('is empty for a lone pane', () {
      final expected = <String>{};

      final ids = Workspace.single('a').collapsibleIds;

      expect(ids, expected);
    });

    test('excludes panes in a row split', () {
      final expected = <String>{};

      final ids = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').collapsibleIds;

      expect(ids, expected);
    });

    test('includes every direct child of a 2+-row column', () {
      final expected = {'a', 'b'};

      final ids = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').collapsibleIds;

      expect(ids, expected);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — `collapsedIds`, `toggleCollapse`, and `collapsibleIds` are undefined on `Workspace`.

- [ ] **Step 3: Implement `collapsedIds`, `toggleCollapse`, and the direct-parent gate**

In `lib/workspace.dart`, replace the constructor and field declarations (current lines 9–16):

```dart
  const Workspace({
    required this.root,
    required this.focusedId,
    this.collapsedIds = const {},
  });

  /// The window holding a single session — how the app starts.
  factory Workspace.single(String sessionId) =>
      Workspace(root: PaneNode(sessionId), focusedId: sessionId);

  final LayoutNode root;
  final String focusedId;

  /// Session ids currently the sole expanded row within their own
  /// direct-parent column. Scoped per column: two entries can coexist
  /// freely as long as they belong to different columns, since a
  /// column's own other rows are never independently reachable while one
  /// of their siblings is the expanded one.
  final Set<String> collapsedIds;
```

Add these methods to the `Workspace` class, just after `focus()` (current lines 28–29):

```dart
  /// Sets [sessionId] as the sole expanded row within its own direct-parent
  /// column, or restores that column to even shares if [sessionId] was
  /// already the expanded one. No-ops when [sessionId]'s direct parent
  /// isn't a column split with 2+ children — the one gate every caller
  /// (a bar click, a hotkey) gets for free by going through here.
  Workspace toggleCollapse(String sessionId) {
    final parent = _directParent(root, sessionId);
    if (parent == null ||
        parent.axis != SplitAxis.column ||
        parent.children.length < 2) {
      return this;
    }

    final siblingIds = {
      for (final child in parent.children)
        if (child is PaneNode) child.sessionId,
    };
    final updated = {...collapsedIds}..removeAll(siblingIds);
    if (!collapsedIds.contains(sessionId)) updated.add(sessionId);

    return Workspace(root: root, focusedId: sessionId, collapsedIds: updated);
  }

  /// Every session whose direct parent is a column split with 2+ children —
  /// the panes a bar's collapse affordance should appear on.
  Set<String> get collapsibleIds {
    final ids = <String>{};
    _collectCollapsible(root, ids);
    return ids;
  }

  static void _collectCollapsible(LayoutNode node, Set<String> into) {
    if (node is PaneNode) return;
    final split = node as SplitNode;
    if (split.axis == SplitAxis.column && split.children.length >= 2) {
      for (final child in split.children) {
        if (child is PaneNode) into.add(child.sessionId);
      }
    }
    for (final child in split.children) {
      _collectCollapsible(child, into);
    }
  }

  /// The nearest ancestor split holding [sessionId] as a direct child, or
  /// null if [sessionId] is the whole tree (no parent at all).
  static SplitNode? _directParent(LayoutNode node, String sessionId) {
    if (node is PaneNode) return null;
    final split = node as SplitNode;
    for (final child in split.children) {
      if (child is PaneNode && child.sessionId == sessionId) return split;
    }
    for (final child in split.children) {
      final found = _directParent(child, sessionId);
      if (found != null) return found;
    }
    return null;
  }
```

Update `focus()` (current lines 28–29) to thread `collapsedIds` through:

```dart
  Workspace focus(String sessionId) =>
      Workspace(root: root, focusedId: sessionId, collapsedIds: collapsedIds);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — all new and existing tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/workspace.dart test/workspace_test.dart
git commit -m "Add Workspace.toggleCollapse with the direct-parent column gate"
```

---

### Task 2: `close`, `split`, and `reveal` — keeping collapse state coherent

**Files:**
- Modify: `lib/workspace.dart`
- Test: `test/workspace_test.dart`

**Interfaces:**
- Consumes: `Workspace.collapsedIds`, `Workspace._directParent` (from Task 1).
- Produces: `Workspace.reveal(String sessionId) -> Workspace`; `close`/`split`/`resizeSplit` now thread `collapsedIds`.

- [ ] **Step 1: Write the failing tests**

Add to `test/workspace_test.dart`, inside the existing `group('Workspace.close', ...)` block (after its last test, before that group's closing `});` around what is currently line 166):

```dart
    test('clears its own column\'s collapse entry when the collapsed pane closes', () {
      final expected = <String>{};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .toggleCollapse('b')
          .close('b');

      expect(workspace!.collapsedIds, expected);
    });

    test('leaves an unrelated column\'s collapse entry alone', () {
      final expected = {'d'};

      // (a over b) | (c over d) — collapse the right column to 'd', then
      // close a pane entirely inside the left column.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .split(axis: SplitAxis.column, newSessionId: 'd')
          .toggleCollapse('d')
          .close('b');

      expect(workspace!.collapsedIds, expected);
    });
```

Add a new group at the end of the file, just before the closing `}` (after the group added in Task 1):

```dart
  group('Workspace.split clearing collapse', () {
    test('splitting into an already-collapsed column reveals the new pane', () {
      final expected = <String>{};

      // Column of (a over b), collapsed to 'a'. Focusing 'a' and splitting
      // it along the column axis inserts 'c' as a new sibling row in the
      // same column — which must reveal the whole column again.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('a')
          .split(axis: SplitAxis.column, newSessionId: 'c');

      expect(workspace.collapsedIds, expected);
    });

    test('splitting a different, uncollapsed column leaves collapse alone', () {
      final expected = {'b'};

      // (a over b), collapsed to 'b'. A fresh row split off the whole tree
      // wraps the root in a new row — 'b' stays exactly where it was, in
      // the same column, so its collapse survives untouched.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b')
          .split(axis: SplitAxis.row, newSessionId: 'c');

      expect(workspace.collapsedIds, expected);
    });
  });

  group('Workspace.reveal', () {
    test('clears the entry hiding a sibling in the same column', () {
      final expected = <String>{};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('a')
          .reveal('b');

      expect(workspace.collapsedIds, expected);
    });

    test('is a no-op when the target is not hidden by any collapse', () {
      final expected = <String>{};

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').reveal('b');

      expect(workspace.collapsedIds, expected);
    });

    test('leaves a different column\'s collapse untouched', () {
      final expected = {'d'};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .split(axis: SplitAxis.column, newSessionId: 'd')
          .toggleCollapse('d')
          .reveal('b');

      expect(workspace.collapsedIds, expected);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/workspace_test.dart`
Expected: FAIL — `Workspace.reveal` is undefined; the `close`/`split` collapse-clearing tests fail because `collapsedIds` isn't threaded through those methods yet (they'll report an empty set as the *default*, but the "leaves ... alone" cases will fail since nothing preserves a pre-existing entry either).

- [ ] **Step 3: Implement `reveal` and thread `collapsedIds` through `close`/`split`/`resizeSplit`**

Add to the `Workspace` class, just after `toggleCollapse` (added in Task 1):

```dart
  /// Clears whichever collapse entry (if any) is currently hiding
  /// [sessionId] behind a different sibling in the same column, so
  /// [sessionId] becomes visible. A no-op if [sessionId] isn't hidden.
  Workspace reveal(String sessionId) {
    final parent = _directParent(root, sessionId);
    if (parent == null) return this;

    final siblingIds = {
      for (final child in parent.children)
        if (child is PaneNode) child.sessionId,
    };
    final hiding = collapsedIds.intersection(siblingIds)..remove(sessionId);
    if (hiding.isEmpty) return this;

    return Workspace(
      root: root,
      focusedId: focusedId,
      collapsedIds: collapsedIds.difference(hiding),
    );
  }
```

Replace `split()` (current lines 39–45) with:

```dart
  Workspace split({required SplitAxis axis, required String newSessionId}) {
    final wrapped = _wrapIfFocused(root, axis, newSessionId);
    return Workspace(
      root: wrapped ?? _insertBeside(root, axis, newSessionId),
      focusedId: newSessionId,
      collapsedIds: collapsedIds,
    ).reveal(newSessionId);
  }
```

Replace `close()` (current lines 54–63) with:

```dart
  Workspace? close(String sessionId) {
    final remaining = _without(root, sessionId);
    if (remaining == null) return null;

    final ids = _idsOf(remaining);
    return Workspace(
      root: remaining,
      focusedId: ids.contains(focusedId) ? focusedId : ids.first,
      collapsedIds: collapsedIds.where((id) => id != sessionId).toSet(),
    );
  }
```

Replace `resizeSplit()` (current lines 126–135) with:

```dart
  Workspace resizeSplit({
    required LayoutNode split,
    required int dividerIndex,
    required double delta,
  }) {
    return Workspace(
      root: _resized(root, split, dividerIndex, delta),
      focusedId: focusedId,
      collapsedIds: collapsedIds,
    );
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/workspace_test.dart`
Expected: PASS — every test in the file, old and new.

- [ ] **Step 5: Commit**

```bash
git add lib/workspace.dart test/workspace_test.dart
git commit -m "Keep Workspace.collapsedIds coherent across close, split, and focus moves"
```

---

### Task 3: The `ToggleCollapse` hotkey

**Files:**
- Modify: `lib/split_shortcuts.dart`
- Test: `test/split_shortcuts_test.dart`

**Interfaces:**
- Produces: `ToggleCollapse` (a `PaneAction` subclass with no fields), bound to `Shift+Alt+Z` (Windows) and `Cmd+Shift+Enter` (macOS).

- [ ] **Step 1: Write the failing tests**

Add to `test/split_shortcuts_test.dart`, inside `group('macOS', ...)`, after the `'Cmd+Opt+Left moves focus left'` test (before that group's closing test about `'Cmd+Shift+W is left for the terminal'`):

```dart
    test('Cmd+Shift+Enter toggles collapse', () {
      final action = macAction(
        LogicalKeyboardKey.enter,
        meta: true,
        shift: true,
      );

      expect(action, isA<ToggleCollapse>());
    });
```

Add to `test/split_shortcuts_test.dart`, inside `group('Windows', ...)`, after the `'Alt+Down moves focus down'` test (before the `'Ctrl+D is never bound'` test):

```dart
    test('Alt+Shift+Z toggles collapse', () {
      final action = windowsAction(
        LogicalKeyboardKey.keyZ,
        alt: true,
        shift: true,
      );

      expect(action, isA<ToggleCollapse>());
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `fvm flutter test test/split_shortcuts_test.dart`
Expected: FAIL — `ToggleCollapse` is undefined.

- [ ] **Step 3: Implement `ToggleCollapse` and its two hotkeys**

In `lib/split_shortcuts.dart`, add a new `PaneAction` subclass after `MoveFocus` (current lines 20–24):

```dart
class ToggleCollapse extends PaneAction {
  const ToggleCollapse();
}
```

In `_windowsAction` (current lines 62–88), inside the existing `if (!isControlPressed && isShiftPressed && isAltPressed) { ... }` block that already handles the split keys, add the new key check alongside `equal`/`minus`:

```dart
  if (!isControlPressed && isShiftPressed && isAltPressed) {
    if (key == LogicalKeyboardKey.equal) return const SplitPane(SplitAxis.row);
    if (key == LogicalKeyboardKey.minus) {
      return const SplitPane(SplitAxis.column);
    }
    if (key == LogicalKeyboardKey.keyZ) return const ToggleCollapse();
  }
```

In `_macAction` (current lines 91–114), add a new branch just before the final `return null;`:

```dart
  if (isMetaPressed &&
      isShiftPressed &&
      !isAltPressed &&
      key == LogicalKeyboardKey.enter) {
    return const ToggleCollapse();
  }
  return null;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `fvm flutter test test/split_shortcuts_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/split_shortcuts.dart test/split_shortcuts_test.dart
git commit -m "Add the ToggleCollapse hotkey: Shift+Alt+Z / Cmd+Shift+Enter"
```

---

### Task 4: `PaneBar`, `PaneView`, `SplitView`, `WorkspaceView` — the collapse-aware rendering, wired end to end

**Why one task:** every new parameter these four files add is `required`. `PaneView` requires arguments only `SplitView` can supply; `SplitView` requires arguments only `WorkspaceView` can supply. None of the four compiles against the others' *old* shape — there is no intermediate point between "start" and "all four done" where `fvm flutter test` can run at all, let alone meaningfully pass or fail. Splitting this into per-file tasks would produce tasks whose own verification step is "doesn't compile yet, that's expected" — not a real deliverable. So all four land as one task, with one compile-and-test check at the end.

**Files:**
- Modify: `lib/pane_bar.dart`
- Modify: `lib/pane_view.dart`
- Modify: `lib/split_view.dart`
- Modify: `lib/workspace_view.dart`

**Interfaces:**
- Consumes: `Workspace.collapsedIds` / `collapsibleIds` / `toggleCollapse` / `reveal` (Task 1/2), `ToggleCollapse` (Task 3).
- Produces: the fully wired click-to-collapse and hotkey-to-collapse behavior — nothing later depends on this task.

No automated test exists for this widget layer in this project (see Global Constraints) — verified by eye in Task 5's manual pass. `fvm flutter test`/`fvm flutter analyze` here only confirm the whole app still compiles clean and no existing unit test regressed.

- [ ] **Step 1: Update `PaneBar` to take `canCollapse`/`collapsed` and show the affordance**

A concurrent merge (the "pane title" feature, `docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md`) landed in this file since this plan was written: `session.title` no longer exists — it split into `session.name` (OSC 1) and `session.activity` (OSC 2), combined via `paneTitle(name:, activity:)` from the new `pane_title.dart`. The replacement below keeps that intact and adds only the collapse affordance on top. If `lib/pane_bar.dart` has changed again since, reconcile by hand rather than blindly overwriting — the same caution applies to Step 2.

Replace the full contents of `lib/pane_bar.dart`:

```dart
import 'package:flutter/material.dart';

import 'pane_title.dart';
import 'session.dart';

/// The thin strip naming a pane.
///
/// Carries a title, and — when [canCollapse] is true — a small collapse
/// affordance a tap on the bar (wired by the caller, not here) toggles.
class PaneBar extends StatelessWidget {
  const PaneBar({
    super.key,
    required this.session,
    required this.focused,
    required this.canCollapse,
    required this.collapsed,
  });

  static const height = 22.0;

  final Session session;
  final bool focused;
  final bool canCollapse;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: focused ? scheme.surfaceContainerHighest : scheme.surfaceContainer,
      child: Row(
        children: [
          Expanded(child: _title(scheme)),
          if (canCollapse) _collapseIcon(scheme),
        ],
      ),
    );
  }

  Widget _collapseIcon(ColorScheme scheme) => Text(
    collapsed ? '⤡' : '⤢',
    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
  );

  Widget _title(ColorScheme scheme) {
    return ValueListenableBuilder(
      valueListenable: session.name,
      builder: (context, name, child) => ValueListenableBuilder(
        valueListenable: session.activity,
        builder: (context, activity, child) => Text(
          paneTitle(name: name, activity: activity),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: focused ? FontWeight.w700 : FontWeight.w400,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Update `PaneView` to wire the tap and skip the terminal when shrunk**

The same concurrent merge added a `ClipRect` around `TerminalView` in this file (xterm's `RenderTerminal` doesn't clip its own paint, so a scroll could otherwise draw into `PaneBar`). The replacement below keeps that wrapper and adds only the tap handler and the `shrunk` branch.

Replace the full contents of `lib/pane_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'pane_bar.dart';
import 'session.dart';

/// One pane: its bar, and the terminal beneath — unless [shrunk], in which
/// case only the bar renders, at its own fixed height, and the terminal is
/// skipped entirely. A pane's [Session] outlives this widget either way.
class PaneView extends StatelessWidget {
  const PaneView({
    super.key,
    required this.session,
    required this.focused,
    required this.onFocus,
    required this.onKeyEvent,
    required this.canCollapse,
    required this.collapsed,
    required this.shrunk,
    required this.onToggleCollapse,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;
  final FocusOnKeyEventCallback onKeyEvent;
  final bool canCollapse;
  final bool collapsed;
  final bool shrunk;
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
          if (!shrunk)
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

- [ ] **Step 3: Replace `lib/split_view.dart` with the collapse-aware rendering**

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
/// delta and lets the tree decide what it means. A column with one of its
/// direct children in [collapsedIds] renders that child at full size and
/// every other direct pane child as a bar-only strip — see
/// [_buildCollapsedSplitChildren].
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

  Widget _pane(String sessionId) => _shrinkablePane(sessionId, shrunk: false);

  Widget _shrinkablePane(String sessionId, {required bool shrunk}) {
    final session = sessions[sessionId];
    if (session == null) return const SizedBox.shrink();
    return PaneView(
      session: session,
      focused: sessionId == focusedId,
      onFocus: () => onFocus(sessionId),
      onKeyEvent: onKeyEvent,
      canCollapse: collapsibleIds.contains(sessionId),
      collapsed: collapsedIds.contains(sessionId),
      shrunk: shrunk,
      onToggleCollapse: () => onToggleCollapse(sessionId),
    );
  }

  /// The direct child of [split] currently expanded, or null if none of
  /// [split]'s direct pane children is in [collapsedIds] — including
  /// whenever [split] doesn't run the column axis at all.
  String? _expandedChildId(SplitNode split) {
    if (split.axis != SplitAxis.column) return null;
    for (final child in split.children) {
      if (child is PaneNode && collapsedIds.contains(child.sessionId)) {
        return child.sessionId;
      }
    }
    return null;
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
        final expandedId = _expandedChildId(split);

        final children = expandedId == null
            ? _buildEvenSplitChildren(split, context, horizontal, free)
            : _buildCollapsedSplitChildren(split, horizontal, free, expandedId);

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

  List<Widget> _buildEvenSplitChildren(
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
      children.add(_buildEvenSplitChild(split, i, horizontal, free));
    }
    return children;
  }

  Widget _buildEvenSplitChild(
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

  /// Sizes a collapsed column's children: the expanded row absorbs every
  /// bit of space its shrunk pane-siblings gave up. A sibling that is
  /// itself a nested split (not a bare pane) has no single bar to shrink
  /// to, so it keeps its ordinary ratio-based share untouched — a known,
  /// accepted edge case rather than something this generalizes further.
  /// No dividers: a fixed-height shrunk row isn't draggable.
  List<Widget> _buildCollapsedSplitChildren(
    SplitNode split,
    bool horizontal,
    double free,
    String expandedId,
  ) {
    var fixedTotal = 0.0;
    var ratioTotal = 0.0;
    for (var i = 0; i < split.children.length; i++) {
      final child = split.children[i];
      if (child is PaneNode && child.sessionId != expandedId) {
        fixedTotal += PaneBar.height;
      } else if (child is SplitNode) {
        ratioTotal += free * split.ratios[i];
      }
    }
    final expandedSize = free - fixedTotal - ratioTotal;

    final children = <Widget>[];
    for (var i = 0; i < split.children.length; i++) {
      final child = split.children[i];
      if (child is PaneNode) {
        final isExpanded = child.sessionId == expandedId;
        final size = isExpanded ? expandedSize : PaneBar.height;
        children.add(
          SizedBox(
            width: horizontal ? size : null,
            height: horizontal ? null : size,
            child: _shrinkablePane(child.sessionId, shrunk: !isExpanded),
          ),
        );
      } else {
        final size = free * split.ratios[i];
        children.add(
          SizedBox(
            width: horizontal ? size : null,
            height: horizontal ? null : size,
            child: _childSplitView(child),
          ),
        );
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

- [ ] **Step 4: Add the toggle handler to `WorkspaceView` and wire it into `build()`**

In `lib/workspace_view.dart`, add a new method just after `_onPaneFocus` (current lines 85–88):

```dart
  void _toggleCollapse(String id) {
    setState(() => workspace = workspace.toggleCollapse(id));
  }
```

Update `_moveFocus` (current lines 78–83) to reveal the target before focusing it:

```dart
  void _moveFocus(Direction direction) {
    final target = workspace.neighbour(direction);
    if (target == null) return;
    setState(() => workspace = workspace.focus(target).reveal(target));
    _requestFocus(target);
  }
```

Update `_dispatch` (current lines 148–157) to handle the new action:

```dart
  void _dispatch(PaneAction action) {
    switch (action) {
      case SplitPane(:final axis):
        _split(axis);
      case ClosePane():
        _close(workspace.focusedId);
      case MoveFocus(:final direction):
        _moveFocus(direction);
      case ToggleCollapse():
        _toggleCollapse(workspace.focusedId);
    }
  }
```

Update the `import 'split_shortcuts.dart';`-based usage: no import change needed, `ToggleCollapse` is already exported from that file (Task 3).

Update the `build()` method's `SplitView(...)` call (current lines 171–184) to pass the three new parameters:

```dart
  @override
  Widget build(BuildContext context) {
    return Focus(
      // Re-runs _onKey for keys a terminal returns `ignored` on; see
      // _onKey's doc for why this is not a backstop for the no-focus case.
      onKeyEvent: _onKey,
      child: SplitView(
        node: workspace.root,
        sessions: sessions,
        focusedId: workspace.focusedId,
        collapsedIds: workspace.collapsedIds,
        collapsibleIds: workspace.collapsibleIds,
        onFocus: _onPaneFocus,
        onKeyEvent: _onKey,
        onToggleCollapse: _toggleCollapse,
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
```

- [ ] **Step 5: Run the full test suite**

Run: `fvm flutter test`
Expected: PASS — every unit test in the project, all four files now compile together against each other's real shapes.

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/pane_bar.dart lib/pane_view.dart lib/split_view.dart lib/workspace_view.dart
git commit -m "Wire pane collapse end to end: bar click, hotkey, and shrunk rendering"
```

---

### Task 5: Manual verification, both platforms

**Files:** none (verification only).

- [ ] **Step 1: Launch on Windows**

Run: `fvm flutter run -d windows`
Expected: app builds and launches with no console errors.

- [ ] **Step 2: Build a 3-row column and collapse the first row**

In the running app: split the initial pane into a column three times (same axis, same side each time) so one column holds 3 stacked rows. Click the first row's bar.
Expected: first row expands to fill the reclaimed space; rows 2 and 3 shrink to bar-only strips beneath it, in their original order (matching the `/henneth` wireframe's State 5).

- [ ] **Step 3: Collapse the middle row instead**

From the same 3-row column (restore first, if needed, by clicking the expanded row's own bar), click the middle row's bar.
Expected: the middle row expands in place — row 1 shrinks above it, row 3 shrinks below it. Neither shrunk row moves position (matches State 6).

- [ ] **Step 4: Confirm a shrunk sibling's bar switches the expansion directly**

With one row expanded, click a different (shrunk) sibling's bar.
Expected: the click switches which row is expanded in one action — no need to restore first.

- [ ] **Step 5: Confirm two columns collapse independently**

Split the workspace into two side-by-side columns, each itself a 2-row stack. Collapse a row in the left column, then a different row in the right column.
Expected: both stay collapsed simultaneously, each to its own chosen row; neither column's state affected the other's.

- [ ] **Step 6: Confirm the gate on non-collapsible panes**

Check a pane alone in its own column (no split), and a pane inside a side-by-side (row) split.
Expected: neither shows the ⤢/⤡ affordance on its bar; the hotkey does nothing when either is focused.

- [ ] **Step 7: Confirm the busy-spinner still shows on a shrunk row**

Collapse a column so that a sibling running a long-lived command (e.g. `claude`, or `tail -f` against a growing file) is shrunk to bar-only.
Expected: that sibling's busy-spinner (from Milestone 1) is still visible on its shrunk bar while it's producing output.

- [ ] **Step 8: Confirm the hotkey mirrors the click**

Focus a collapsible pane and press `Shift+Alt+Z`.
Expected: same effect as clicking that pane's own bar — collapses it, or restores it if it was already the expanded one.

- [ ] **Step 9: Confirm split/move-focus reveal a hidden row**

With a column collapsed to one row, use `Alt+Arrow` to move focus onto a currently-shrunk sibling in the same column; separately, with a column collapsed, split the expanded row along the column axis.
Expected: both actions reveal (expand) the newly-relevant row, matching the design's `reveal` behavior.

- [ ] **Step 10: Repeat the launch and the same checks on macOS**

Run: `fvm flutter run -d macos`
Expected: all of Steps 2–9 hold identically, with `Cmd+Shift+Enter` in place of `Shift+Alt+Z`.

- [ ] **Step 11: Run the full automated suite one last time**

Run: `fvm flutter test`
Expected: PASS, same as Task 4's final check — confirms nothing drifted between the last commit and the manual walk.

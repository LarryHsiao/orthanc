# Orthanc — Pane Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user right-click a pane bar, choose "Rename," and set a name of their own that shows as a leading prefix in the pane's title — independent of anything the running program sets via OSC.

**Architecture:** `Session` gains a third `ValueNotifier<String> manualName`, written only by the UI. `paneTitle()` gains an optional `manualName` parameter it prepends to its existing `name — activity` combine. `PaneBar` becomes a `StatefulWidget` that opens a `showMenu` context menu on right-click (`onSecondaryTapUp`) with a single "Rename" entry, swaps its title `Text` for a `TextField` in edit mode, and commits on Enter / cancels on Esc. `PaneView` and `SplitView` are untouched — the menu trigger lives entirely inside `PaneBar`, since it already owns the `BuildContext` and (as of this plan) the local edit-mode state; no callback needs threading through the layout tree.

**Tech Stack:** Flutter (Dart SDK `^3.10.7`), `flutter_test` for widget/unit tests. No new dependencies — `showMenu`/`PopupMenuItem` come from `package:flutter/material.dart`, already imported everywhere this plan touches.

## Global Constraints

- No new pubspec dependencies.
- No persistence — `manualName` lives only on the in-memory `Session`, same lifetime as `activity`/`name`/`terminal`.
- Never wire `manualName` to any OSC channel — it must stay a name no running program can overwrite (see the design spec's Why).
- All title-combining logic stays inside `paneTitle()` (`lib/pane_title.dart`) — `PaneBar` must not grow parallel string-concatenation logic for the prefix.
- Match existing code style in this repo: `final` locals/fields by default, doc comments only where a non-obvious constraint or invariant needs stating (see the existing doc comments in `lib/session.dart` and `lib/pane_title.dart` for the register to match).

---

## Task 1: `Session.manualName`

**Files:**
- Modify: `lib/session.dart:36-38` (after the existing `name` notifier), and `lib/session.dart:122-129` (`dispose()`)
- Test: `test/session_test.dart`

**Interfaces:**
- Produces: `Session.manualName` — `ValueNotifier<String>`, starts at `''`, disposed by `Session.dispose()`. Read by `PaneBar` (Task 3) and passed into `paneTitle()` (Task 2).

- [ ] **Step 1: Write the failing test**

Add to `test/session_test.dart`, after the existing `'starts with no name'` test (currently ending at line 29):

```dart
  test('starts with no manual name', () {
    const expectedManualName = '';

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.manualName.value, expectedManualName);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/session_test.dart`
Expected: FAIL — `The getter 'manualName' isn't defined for the type 'Session'`

- [ ] **Step 3: Add the notifier and wire it into dispose()**

In `lib/session.dart`, add immediately after the existing `name` notifier (after line 38, `late final ValueNotifier<String> name = ValueNotifier('');`):

```dart

  /// A name the user sets directly, via [PaneBar]'s rename control —
  /// independent of anything the running program sets. See
  /// docs/superpowers/specs/2026-07-23-orthanc-pane-rename-design.md.
  late final ValueNotifier<String> manualName = ValueNotifier('');
```

Then in `dispose()` (currently `lib/session.dart:122-129`), add `manualName.dispose();` alongside the other two:

```dart
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_processExited) _pty?.kill();
    focusNode.dispose();
    activity.dispose();
    name.dispose();
    manualName.dispose();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/session_test.dart`
Expected: PASS — all tests in the file green, including the new one.

- [ ] **Step 5: Commit**

```bash
git add lib/session.dart test/session_test.dart
git commit -m "feat: add Session.manualName for user-set pane names"
```

---

## Task 2: `paneTitle()` gains `manualName`

**Files:**
- Modify: `lib/pane_title.dart`
- Test: `test/pane_title_test.dart`

**Interfaces:**
- Consumes: nothing new (pure function, no dependency on Task 1).
- Produces: `paneTitle({required String name, required String activity, String manualName = ''})` — returns `'$manualName — $base'` when `manualName` is non-empty, `base` (today's `name`/`activity` combine) otherwise. Called by `PaneBar` in Task 3 with `manualName: widget.session.manualName.value`.

- [ ] **Step 1: Write the failing tests**

Add to `test/pane_title_test.dart`, inside the existing `main()`, after the current three tests:

```dart

  test('prefixes manualName ahead of activity when set', () {
    const expected = 'api-refactor — check status';

    final result = paneTitle(
      name: '',
      activity: 'check status',
      manualName: 'api-refactor',
    );

    expect(result, expected);
  });

  test('omits manualName prefix when empty', () {
    const expected = 'check status';

    final result = paneTitle(
      name: '',
      activity: 'check status',
      manualName: '',
    );

    expect(result, expected);
  });

  test('prefixes manualName ahead of the collapsed name-equals-activity case', () {
    const expected = 'api-refactor — ✳ Claude Code';

    final result = paneTitle(
      name: '✳ Claude Code',
      activity: '✳ Claude Code',
      manualName: 'api-refactor',
    );

    expect(result, expected);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/pane_title_test.dart`
Expected: FAIL — `No named parameter with the name 'manualName'`

- [ ] **Step 3: Add the parameter and prefix logic**

Replace the full contents of `lib/pane_title.dart` with:

```dart
/// Combines a session's manual name, program-set name, and current
/// activity into one line for [PaneBar]. [manualName] — set by the user via
/// [PaneBar]'s rename control, never by the running program — prefixes
/// whatever [name] and [activity] already combine to, when set. See
/// docs/superpowers/specs/2026-07-23-orthanc-pane-rename-design.md and
/// docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md.
///
/// Claude Code sets its title via OSC 0, which sets [name] and [activity]
/// to the identical string in one call (confirmed empirically — see the
/// pane-title spec's "Verified 2026-07-22" note) — so a [name] equal to
/// [activity] is treated the same as an empty one, or the pane bar would
/// show the value twice.
String paneTitle({
  required String name,
  required String activity,
  String manualName = '',
}) {
  final base = (name.isEmpty || name == activity)
      ? activity
      : '$name — $activity';
  if (manualName.isEmpty) return base;
  return '$manualName — $base';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/pane_title_test.dart`
Expected: PASS — all six tests in the file green.

- [ ] **Step 5: Commit**

```bash
git add lib/pane_title.dart test/pane_title_test.dart
git commit -m "feat: prefix paneTitle() with an optional manual name"
```

---

## Task 3: `PaneBar` rename UI

**Files:**
- Modify: `lib/pane_bar.dart` (full rewrite — `StatelessWidget` → `StatefulWidget`)
- Test: Create `test/pane_bar_test.dart`

**Interfaces:**
- Consumes: `Session.manualName` (Task 1), `paneTitle({name, activity, manualName})` (Task 2).
- Produces: `PaneBar`'s public constructor is unchanged (`session`, `focused`, `canCollapse`, `collapsed`) — callers in `lib/pane_view.dart` need no changes.

- [ ] **Step 1: Write the failing widget tests**

Create `test/pane_bar_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pane_bar.dart';
import 'package:orthanc/session.dart';

void main() {
  Future<Session> pumpPaneBar(WidgetTester tester) async {
    final session = Session(id: 'a', executable: 'cmd.exe');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneBar(
            session: session,
            focused: true,
            canCollapse: false,
            collapsed: false,
          ),
        ),
      ),
    );
    return session;
  }

  Future<void> openRenameMenu(WidgetTester tester) async {
    await tester.tap(
      find.byType(PaneBar),
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
  }

  testWidgets('right-click then Rename opens an edit field', (tester) async {
    await pumpPaneBar(tester);

    await openRenameMenu(tester);

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('submitting a name commits it to session.manualName', (
    tester,
  ) async {
    final session = await pumpPaneBar(tester);
    await openRenameMenu(tester);
    const expected = 'api-refactor';

    await tester.enterText(find.byType(TextField), expected);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(session.manualName.value, expected);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('submitting an empty name clears session.manualName', (
    tester,
  ) async {
    final session = await pumpPaneBar(tester);
    session.manualName.value = 'old-name';
    await openRenameMenu(tester);
    const expected = '';

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(session.manualName.value, expected);
  });

  testWidgets('Esc cancels without mutating session.manualName', (
    tester,
  ) async {
    final session = await pumpPaneBar(tester);
    session.manualName.value = 'old-name';
    const expected = 'old-name';
    await openRenameMenu(tester);

    await tester.enterText(find.byType(TextField), 'discarded');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(session.manualName.value, expected);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'field is prefilled with the current manual name when reopened',
    (tester) async {
      final session = await pumpPaneBar(tester);
      session.manualName.value = 'existing-name';
      const expected = 'existing-name';

      await openRenameMenu(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, expected);
    },
  );
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/pane_bar_test.dart`
Expected: FAIL — the first test fails because right-clicking `PaneBar` opens no menu (no `onSecondaryTapUp` handler exists yet), so `find.text('Rename')` in `openRenameMenu()` matches nothing and the `tester.tap` call throws.

- [ ] **Step 3: Rewrite PaneBar as a StatefulWidget**

Replace the full contents of `lib/pane_bar.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pane_title.dart';
import 'session.dart';

/// The thin strip naming a pane.
///
/// Carries a title, and — when [canCollapse] is true — a small collapse
/// affordance a tap on the bar (wired by the caller, not here) toggles.
/// Right-click opens a context menu to rename the pane; the resulting name
/// lives on [Session.manualName], set only from here, never by the running
/// program. See docs/superpowers/specs/2026-07-23-orthanc-pane-rename-design.md.
class PaneBar extends StatefulWidget {
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
  State<PaneBar> createState() => _PaneBarState();
}

class _PaneBarState extends State<PaneBar> {
  bool _editing = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showRenameMenu(context, details.globalPosition),
      child: Container(
        height: PaneBar.height,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: widget.focused
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainer,
        child: Row(
          children: [
            Expanded(child: _editing ? _editField(scheme) : _title(scheme)),
            if (widget.canCollapse) _collapseIcon(scheme),
          ],
        ),
      ),
    );
  }

  Widget _collapseIcon(ColorScheme scheme) => Text(
    widget.collapsed ? '⤡' : '⤢',
    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
  );

  Widget _title(ColorScheme scheme) {
    return ValueListenableBuilder(
      valueListenable: widget.session.manualName,
      builder: (context, manualName, child) => ValueListenableBuilder(
        valueListenable: widget.session.name,
        builder: (context, name, child) => ValueListenableBuilder(
          valueListenable: widget.session.activity,
          builder: (context, activity, child) => Text(
            paneTitle(name: name, activity: activity, manualName: manualName),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: widget.focused ? FontWeight.w700 : FontWeight.w400,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _editField(ColorScheme scheme) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEditing();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(fontSize: 11, color: scheme.onSurface),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
        ),
        onSubmitted: _commitEditing,
      ),
    );
  }

  Future<void> _showRenameMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [PopupMenuItem(value: 'rename', child: Text('Rename'))],
    );
    if (selected == 'rename') _startEditing();
  }

  void _startEditing() {
    _controller.text = widget.session.manualName.value;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
  }

  void _commitEditing(String value) {
    widget.session.manualName.value = value.trim();
    setState(() => _editing = false);
  }

  void _cancelEditing() {
    setState(() => _editing = false);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/pane_bar_test.dart`
Expected: PASS — all five widget tests green.

- [ ] **Step 5: Run the full test suite to check for regressions**

Run: `flutter test`
Expected: PASS — every test in the project green, including `test/pane_view_test.dart` / `test/split_view_test.dart` if present (these construct `PaneBar` only through its unchanged public constructor, so no regression is expected).

- [ ] **Step 6: Commit**

```bash
git add lib/pane_bar.dart test/pane_bar_test.dart
git commit -m "feat: rename a pane via right-click context menu"
```

---

## Task 4: Manual verification on a real run

**Files:** none — this task changes no code; it confirms the interaction behaves and looks right, per this project's practice of eyeballing anything a widget test can't fully cover (see `README.md`'s Tests section, and this repo's `CLAUDE.md`-inherited rule that UI changes get exercised by hand before being called done).

- [ ] **Step 1: Run the app**

Run: `flutter run -d macos`
Expected: the app launches with at least one pane.

- [ ] **Step 2: Right-click a pane bar and rename it**

Right-click anywhere on a pane's title bar. Expected: a context menu appears at the cursor with a single "Rename" entry. Click it.

- [ ] **Step 3: Confirm the edit field and commit**

Expected: the title bar's text is replaced by an editable field. Type `test-pane`, press Enter. Expected: the field closes and the title bar now reads `test-pane — <whatever activity/name were showing before>` (or just `test-pane` if the pane had no name/activity yet) — matching the wireframe at `~/.claude/previews/henneth/wireframe-orthanc-pane-rename.html`.

- [ ] **Step 4: Confirm Esc cancels**

Right-click the same pane bar, choose "Rename" again. Expected: the field opens prefilled with `test-pane`, selected. Type something else, then press Esc. Expected: the field closes and the title bar still reads the prefix set in Step 3 (`test-pane`), unchanged.

- [ ] **Step 5: Confirm clearing the name**

Right-click again, choose "Rename," clear the field entirely (or leave only spaces), press Enter. Expected: the title bar reverts to today's program-driven title with no manual prefix.

- [ ] **Step 6: Confirm collapse-tap is unaffected**

On a pane bar where `canCollapse` is true (open a second pane via whatever split hotkey the app already binds, if not already covered by an existing multi-pane layout), single left-click the bar. Expected: it toggles collapse immediately, with no perceptible delay — confirming the design's core trade-off (right-click, not double-click) actually avoided the gesture-arena delay it was chosen to avoid.

No commit — this task is verification only.

---

## Definition of Done

- `flutter test` passes in full, including the six new `paneTitle()` cases, the five new `PaneBar` widget tests, and the pre-existing suite.
- Right-clicking a pane bar and choosing "Rename" lets the user set a name that shows as a leading prefix ahead of the program-driven title.
- Esc cancels cleanly; an empty commit clears the name back to today's behavior.
- Collapse-tap behavior is unchanged — confirmed by hand in Task 4, Step 6.

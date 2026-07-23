# Orthanc — Pane Rename: A User-Set Name, Independent of the Program

## Goal

Let the user give a pane a name of their own choosing, shown as a leading
prefix in `PaneBar`'s title — independent of whatever the running program
sets via OSC. Right-click a pane bar, choose "Rename," type a name, `Enter`
to commit.

## Why this, and why in this shape

Claude Code has its own `/rename` slash command, and the instinct was to
surface *that* name in the pane bar. Empirically capturing raw pty bytes
around a `/rename` call (`\x1b]0;✳ orthanc-pane-test\x07`) confirmed it goes
out on OSC 0 — the same channel Claude Code uses for every other title
update (its default title, its current-task activity). `docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md`
already established that OSC 0 sets `Session.name` and `Session.activity` to
the identical string in one call, and that Orthanc's title design
deliberately does not parse or guess at title *content* to infer meaning
(M1 decision 6, restated there as decision 2's watch-out). Since Claude Code
exposes no channel that distinguishes "this update is a rename" from "this
update is a task announcement," a name set via `/rename` cannot reliably
persist as a separate prefix — the next task-activity update overwrites it,
same as any other title change. Building a heuristic around it (e.g.
matching the icon glyph Claude happens to use) would depend on an unstated
implementation detail of Claude Code's own UI, not a protocol guarantee, and
directly contradicts the "no heuristics" principle the pane-title spec
already committed to.

The fix is to sidestep the ambiguity entirely: a name Orthanc itself holds,
set through Orthanc's own UI, on a state channel no running program can
touch. This also directly addresses decision 5 of the pane-title spec
("No manual rename UI... explicitly out of scope") — that spec deferred it
without ruling it out; this is that follow-up.

## Decisions

1. **A third `ValueNotifier<String> manualName` on `Session`**, alongside
   the existing `name` (OSC 1) and `activity` (OSC 2/0). Defaults to `''`.
   Nothing in `_wire()` ever sets it — it is written only by the UI, per
   decision 3 below. Disposed in `dispose()` alongside the other two
   notifiers.

2. **`paneTitle()` gains an optional `manualName` parameter and prepends
   it** ahead of the existing `name — activity` combine: `'$manualName —
   $base'` when `manualName` is non-empty, `base` (today's output)
   otherwise. This keeps all title-combining logic in the one pure,
   already-tested function rather than splitting it between `pane_title.dart`
   and `PaneBar`.

3. **Right-click (`onSecondaryTapUp`) on the pane bar opens a context menu**
   with a single "Rename" entry, via Flutter's built-in `showMenu` (no new
   dependency — `material` is already imported). This is a new gesture on
   `PaneView`'s existing `GestureDetector` (`lib/pane_view.dart:40`), which
   today wires only `onTap` (collapse toggle, when `canCollapse`).
   Double-click was the first candidate but was rejected during design: that
   `GestureDetector` already uses `onTap` for collapse, and Flutter cannot
   fire `onTap` immediately once the same detector also registers
   `onDoubleTap` — it must wait out the double-tap timeout (~300ms) to rule
   out a second tap, putting a visible delay on every collapse click.
   Right-click (`onSecondaryTapUp`) is a distinct gesture arena from the
   primary tap, so collapse is untouched.

4. **`PaneBar` becomes a `StatefulWidget`.** It needs to hold local
   edit-mode state (`bool _editing`) and a `TextEditingController`, neither
   of which belongs on `Session` — this is transient UI state, not session
   state. Selecting "Rename" from the context menu flips `_editing` to
   `true` and seeds the controller from `session.manualName.value`
   (selected, so typing immediately replaces it). While editing, the title
   `Text` is swapped for a `TextField` in the same slot.

5. **`Enter` commits, `Esc` cancels.** Committing sets
   `session.manualName.value = controller.text.trim()` — an empty or
   whitespace-only commit clears it, falling back to today's
   `paneTitle(name, activity)` output with no prefix. Canceling discards the
   controller's edits and exits edit mode without touching
   `session.manualName`.

6. **No persistence across app restart.** A pty cannot be resumed across a
   restart — a re-opened pane is a fresh process regardless — so a name
   persisted past the session's lifetime would label a session that no
   longer exists. `manualName` lives only on the in-memory `Session` object,
   same lifetime as everything else there (`terminal`, `focusNode`,
   `activity`, `name`).

## Architecture

Changes are confined to the same units the pane-title spec already touched,
plus the gesture layer:

- **`Session`** (`lib/session.dart`) — new `manualName` notifier, disposed
  alongside the existing two.
- **`paneTitle()`** (`lib/pane_title.dart`) — new optional `manualName`
  parameter, prepended per decision 2.
- **`PaneBar`** (`lib/pane_bar.dart`) — `Stateless` → `Stateful`; renders
  either the title `Text` (idle) or a `TextField` (editing) in the same
  slot; owns the `showMenu` call and the commit/cancel handlers.
- **`PaneView`** (`lib/pane_view.dart`) — `GestureDetector` gains
  `onSecondaryTapUp`, wired to a new callback `PaneBar` exposes (e.g.
  `onRequestRename` passed down, or the menu logic lives directly in
  `PaneBar` if `onSecondaryTapUp` is moved onto `PaneBar` itself rather than
  the wrapping `GestureDetector` in `PaneView` — an implementation-plan
  concern, not a design one; either placement satisfies the same contract:
  right-click opens the menu, "Rename" enters edit mode).

## Testing

| Unit | Tested by |
|---|---|
| `paneTitle()` — `manualName` prefixed when set, omitted when empty, still collapses `name == activity` correctly underneath it | unit tests (`pane_title_test.dart`) |
| `PaneBar` — entering edit mode, `Enter` commits to `session.manualName`, `Esc` cancels without mutating it, empty commit clears a previously-set name | widget tests |
| Right-click opens the menu and "Rename" enters edit mode | widget test (simulate `onSecondaryTapUp` / the menu selection callback) |

## Definition of done

Right-clicking a pane bar and choosing "Rename" lets the user type a name;
`Enter` shows it as a leading prefix in the pane's title bar, ahead of
whatever the running program has set; `Esc` cancels cleanly; clearing the
name (empty commit) reverts to today's program-driven title. Collapse-tap
behavior is unchanged — no added delay.

## Deferred — not in this change

- Surfacing Claude Code's own `/rename` value anywhere in Orthanc — ruled
  out by this spec's Why, not merely postponed.
- Persisting `manualName` across app restarts.
- Any other context-menu entries (Close, Split, etc.) — YAGNI until asked
  for.
- Renaming via keyboard shortcut instead of / in addition to the context
  menu.

## Watch out

- Do not wire `manualName` to any OSC channel, now or later — the entire
  point of this design is a name no running program can overwrite. If a
  future request wants Claude Code's `/rename` reflected too, that is a
  different, harder problem (no protocol-level way to distinguish a rename
  from a task update) and should get its own design, not a quiet merge into
  this field.
- Keep `paneTitle()` the single place title strings are combined — do not
  let `PaneBar` grow its own parallel string-concatenation logic for the
  prefix.

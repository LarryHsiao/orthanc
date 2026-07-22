# Orthanc — Pane Collapse/Expand Design

## Goal

Let one row of a stacked column shrink its siblings to bar-only strips and
take their reclaimed space for itself — a per-column zoom, toggled by a
click on any pane's bar or a hotkey — without ever touching a sibling
column beside it.

## Why this, and why now

Milestone 1 deliberately left this out: "No close button, no collapse
control... that is all the bar does in M1." As sessions pile up in one
stacked column, reading one in detail means fighting a cramped rectangle
shared with its neighbors. This closes that gap without a new view mode —
no card-grid overview, no separate screen — by letting a column show one
of its rows at full size on demand.

The design went through one real correction during brainstorming: the
first pass modeled collapse as a window-wide zoom, one pane filling the
whole app. That was wrong — the actual want is local to a column. Two
side-by-side columns must never collapse into one; collapsing a row within
the left column has no business touching the right column at all. The
model below reflects that correction.

## Decisions

1. **Collapse is scoped to one column, never the whole window.** A pane is
   collapsible only when its **direct parent** `SplitNode` has `axis:
   column` and 2+ children. A pane inside a `row` split (side-by-side), or
   one whose nearest column ancestor sits further up the tree than its own
   direct parent, is never collapsible — regardless of depth. Two
   side-by-side columns never merge into one; a column with only one row
   has nothing to collapse into, so no icon appears and its hotkey is
   inert.

2. **Every column tracks its own state independently.** Two different
   columns can each be collapsed to a different row at the same time; there
   is no shared, workspace-wide flag to step on. Collapsing column B has no
   effect on column A's own choice, whatever it is.

3. **The pane bar is the click target, not the terminal body.** A click
   anywhere inside a running session is left alone — cursor placement, text
   selection, xterm's own gesture handling. Only the bar reacts.

4. **One click sets the expanded row directly.** Clicking any bar in a
   2+-row column — the currently-expanded one, a shrunk sibling, one that
   was never focused — makes that row the expanded one for its column in a
   single action. Clicking the bar of the row **already** expanded restores
   the column to even shares (the toggle-off case). There is no
   restore-then-reselect step; switching which row is expanded is always
   one click.

5. **Shrunk, not hidden.** A column's non-selected rows keep their bar —
   title, the existing busy-spinner from Milestone 1's activity indicator,
   the collapse affordance — at a fixed bar height; only the terminal body
   is dropped. This is the reason the feature exists in this shape: a
   hidden session's busy/idle state must still read at a glance even while
   its column is collapsed to a different row.

6. **Row order never changes.** The expanded row stays at its own original
   position in the stack — collapsing the first row leaves it on top;
   collapsing the middle row leaves it in the middle, with one sibling
   shrunk above and one below. Nothing reorders; only heights change. This
   falls out of the rendering loop as a natural consequence (children are
   drawn in the tree's own stored order regardless of which one is
   expanded), not a rule that needs separate enforcement.

7. **A hotkey mirrors the click, acting on the focused pane:**
   `Shift+Alt+Z` (Windows), `Cmd+Shift+Enter` (macOS — iTerm2's own "Toggle
   Maximize Pane" binding, matching the project's stated philosophy of
   wearing each platform's native terminal scheme). Same toggle semantics
   as clicking the focused pane's own bar.

8. **Moving focus or splitting onto a hidden row reveals it.** If
   `Alt+Arrow` lands focus on a row currently shrunk behind a sibling in its
   own column, or a new split lands a pane into an already-collapsed
   column, that column's collapse clears — the same effect as clicking the
   newly-relevant row's bar. Scoped to the one column affected; every other
   column's collapse state is untouched.

## Architecture

**`Workspace`** (`lib/workspace.dart`) gains `collapsedIds: Set<String>` —
each entry is the session id currently expanded within its own direct-parent
column. Multiple entries can coexist freely; a column's own children can
only ever contain one of them at a time in practice, since a column's other
rows aren't independently clickable while one of their siblings is the
expanded one.

- **`toggleCollapse(sessionId)`** walks to `sessionId`'s direct parent. If
  that parent isn't a `column`-axis `SplitNode` with 2+ children, returns
  `this` unchanged (the gate lives here, once, so every caller — click
  handler, hotkey dispatch — gets it for free). Otherwise: if `sessionId`
  is already the entry recorded for that column, remove it (restore even
  shares); otherwise set it (replacing whatever sibling was previously
  recorded for that same column, if any).
- **`close(sessionId)`** clears `sessionId` from `collapsedIds` when it was
  the entry recorded for its column; leaves every other entry untouched.
- **`split(...)`** and focus changes reveal their target: a private
  `_reveal(sessionId)` step clears whichever `collapsedIds` entry (if any)
  is currently hiding `sessionId` behind a different sibling in the same
  column. `split()` applies this to the newly-created pane; `_moveFocus` in
  `workspace_view.dart` applies it to the neighbour before changing focus.
  Plain-click focus (`_onPaneFocus`, fired by every pointer-down in a pane)
  does **not** call this — otherwise an ordinary click inside an expanded,
  collapsed row would silently undo the collapse on every keystroke's
  surrounding click.

**Rendering (`split_view.dart`).** Building a `column`-axis `SplitNode`,
`SplitView` checks whether one of its **direct** children is a `PaneNode`
matching an entry in `collapsedIds`. If so: that child's row takes all the
height remaining after every other direct child reserves exactly
`PaneBar.height`; every other child renders bar-only (its `PaneBar`, fully
live — busy spinner and collapse affordance both work — with no
`TerminalView` beneath it). Rows are still built in the split's own stored
child order, so the expanded row never moves. A direct child that is itself
a nested `SplitNode` rather than a bare pane — a row of the column further
split side-by-side — cannot itself be "the expanded one" (the gate requires
a direct `PaneNode`), and keeps its ordinary proportional share whenever it
isn't the collapsed target; this is a known, accepted edge case rather than
something the design solves generally.

**`PaneBar`** gains a tap handler over the whole bar and a small ⤢/⤡
affordance, shown only when its pane's direct parent qualifies (2+-child
column). Since collapsibility is now a per-pane fact rather than one
workspace-wide boolean, a `Set<String>` of collapsible ids is computed once
per build and threaded down the same way `focusedId` already is.

**`split_shortcuts.dart`** gains a `ToggleCollapse` `PaneAction` and the two
hotkey bindings above, fired on `workspace.focusedId` via
`_dispatch`.

## Testing

| Unit | Tested by |
|---|---|
| `Workspace.toggleCollapse` — sets, clears, switches within a column; no-ops on a row-split pane or a lone pane; independent across two columns | unit tests, no engine |
| `Workspace.close` clearing a column's entry only when its own expanded pane closes | unit tests |
| `Workspace.split` / `_reveal` clearing only the affected column's entry | unit tests |
| `splitShortcuts()` — the two new hotkey cases, both platforms | unit tests |
| Bar-only shrink rendering, busy-spinner visibility while shrunk, click-to-switch, row order under collapse, both hotkeys | by eye, running the app, both platforms |

Same honest line Milestone 1 drew: the data structure is provable; the
pixels are watched.

## Definition of done

Clicking any pane's bar in a 2+-row column expands that row and shrinks its
siblings to bar-only, in their original order, spinner and all; clicking
the expanded row's own bar restores even shares; clicking a shrunk sibling
switches the expansion to it directly; a single-row column and a
side-by-side (row) split show no collapse affordance at all; two different
columns hold independent collapse state at once; the hotkeys mirror the
click on both platforms; moving focus or splitting onto a hidden row
reveals it — confirmed by hand on both macOS and Windows.

## Deferred — not in this change

- Collapse behavior for `row` (side-by-side) splits — this change is
  column-only, by explicit decision.
- A hidden-pane-count indicator (sketched during wireframing, dropped —
  the shrunk bars already carry that signal).
- Persisting collapse state across an app restart.
- Generalizing the shrink-to-bar treatment to a sibling that is itself a
  nested split rather than a bare pane (see the accepted edge case above).

## Watch out

- The gate (`toggleCollapse`'s direct-parent check) is the one place that
  must stay correct — a bug there either makes an uncollapsible pane
  collapsible (breaking the "two columns never merge" guarantee) or
  silently disables a legitimate collapse.
- `_reveal`'s scoping to "only the affected column" is easy to get wrong in
  a way that only shows up with 3+ columns each independently collapsed —
  worth exercising by hand with more than two columns during the walk, not
  just the two the wireframe shows.
- Shrinking a row to bar-only must not tear down its `Session` — the pty
  and terminal buffer must survive exactly as they do today when a pane
  merely moves within the layout.

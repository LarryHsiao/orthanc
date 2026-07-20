# Orthanc — Milestone 1 Design

## Goal

Many Claude Code sessions running at once, all visible simultaneously in one
window as split panes, arranged by hotkey. Milestone 0 proved one session could
render and take input on both platforms; Milestone 1 makes the window hold as
many as the work needs.

## Why this, and why in this shape

The project note names what Orthanc exists to beat: Claude Code's own Agent View
is keyboard-driven rather than one-click, and the Desktop app runs one
foreground session per window with no way to jump between parallel sessions.

The first design pass here proposed a sidebar — a list of sessions, one terminal
on screen. That was wrong, and naming why matters, because it sets the whole
milestone. The win is not *switching quickly between* sessions. It is **not
having to switch at all**. Watching several agents work simultaneously is the
point; a sidebar would still hide five of six.

So the panes split, tmux-style, and everything stays on screen.

## Guiding principle

Put the layout in a plain data structure, not in widgets.

Nothing about the pty/terminal wiring can be unit-tested — the M0 plan says so,
and M0 proved it: three real defects, every one found by running the app, none
by the suite. Milestone 1 adds splitting, closing, reflowing, resizing and
directional focus, and *all of that is pure data-structure work that need never
touch a pty*. Modelled as a tree that knows nothing of Flutter, the riskiest
part of M1 becomes the first genuinely testable part of this project. Modelled
as nested stateful widgets, it repeats M0's predicament at ten times the scale.

Keep the line between "can be proven" and "must be watched" as low as it will go.

## Decisions

Each was taken deliberately in design discussion; the reasoning is recorded so a
later reader can tell a choice from an accident.

1. **Split panes, not a sidebar or tabs.** All sessions visible at once. Tabs
   were rejected on evidence: at six sessions, names already truncate and some
   fall off the strip entirely — it fails exactly where Orthanc is meant to
   shine.

2. **An arbitrary layout tree, split by hotkey.** Not a reflowing grid, not
   fixed columns. The user chooses every division.

3. **The new pane takes the space right or below.** The focused pane keeps its
   position; a vertical split puts the new pane to its right, a horizontal split
   below it.

4. **Hotkeys native to each platform.** macOS follows iTerm2, Windows follows
   Windows Terminal. `Ctrl+D` is deliberately avoided — it is EOF, and would
   kill a session rather than split it. None of the chosen bindings collide with
   Claude Code, which claims `Ctrl+C`, `Ctrl+L`, `Esc` and `Shift+Tab`.

   | | macOS | Windows |
   |---|---|---|
   | split vertical (new pane right) | `Cmd+D` | `Alt+Shift+Plus` |
   | split horizontal (new pane below) | `Cmd+Shift+D` | `Alt+Shift+Minus` |
   | close pane | `Cmd+W` | `Ctrl+Shift+W` |
   | move focus | `Cmd+Opt+arrows` | `Alt+arrows` |

5. **A thin title bar per pane, carrying only a title.** No close button, no
   collapse control — with no tab strip to carry a name, each pane must name
   itself, and that is all the bar does in M1.

6. **The title comes from the program, not from us.** `Terminal.onTitleChange`
   fires on the OSC 0/2 sequence the running program emits — the same title tmux
   and iTerm display. Claude Code writes its current task there. No parsing, no
   heuristics, no Claude-specific knowledge.

7. **A leading icon spins while the session is busy, and is absent otherwise.**
   The slot collapses when idle rather than reserving space. The glyph means
   *work is happening now*, for any session — so there is no session type to
   detect and nothing to get wrong when the spawned command becomes
   configurable.

8. **Busy is inferred from output activity.** There is no busy signal in a pty;
   nothing in the protocol says a program is working. Parsing Claude's own
   spinner glyphs would break whenever Claude changes its UI and would know
   nothing of other agents. Output activity fits by accident of how TUIs work:
   an animating spinner *is* continuous output, and a prompt waiting for input
   emits nothing. Costs one timer per session. **Start at 500ms** and adjust
   only against a running app.

9. **First run opens one session.** There is no empty state — the app opens
   straight into a working terminal, as it does today. Nothing to design, build
   or test.

   **Every new pane spawns the same command that first session does** — today's
   `shellCommand()`, a plain shell, from which the user starts `claude` by hand.
   Choosing a command per pane is deferred, and M0's warning against turning the
   spawned command into a config value still stands.

10. **A finished session closes its own pane; the last one quits the app.**
    Siblings reflow to fill the space. This preserves M0's committed behaviour
    exactly in the one-session case, and makes `Cmd+W` and a typed `exit` mean
    the same thing.

11. **Draggable dividers and hotkey focus movement are both in scope.** Splits
    start even; a drag rewrites one node's ratios.

## Architecture

Four units, each with one job.

**`Session`** — owns one `Pty` and one `Terminal`, and tracks its title and busy
flag. It must **outlive any widget**: a pane that moves within the tree must not
restart its process. This is a real departure from M0, where `PtyTerminal`
creates its `Pty` in `initState` and kills it in `dispose` — correct for one
permanent terminal, wrong the moment a pane can move.

**`LayoutNode`** — a sealed type, either a `PaneNode` holding a session id, or a
`SplitNode` holding an axis, children and ratios. A `row` split lays children
side by side, so its dividers are vertical; a `column` split stacks them, so its
dividers are horizontal. Nesting one inside the other is the entire grammar.

**`Workspace`** — the root node plus the focused session id, with `split`,
`close`, `resize` and `neighbour` as operations. Immutable: every operation
returns a new `Workspace`, so a test is three lines with no setup and no
teardown. It holds only **ids**, never `Session` objects, which is precisely why
it can be exercised without a Flutter engine or a live process.

**`Sessions`** — owns the living sessions by id. The tree owns the arrangement;
this owns the things. Neither knows about the other.

Widgets (`WorkspaceView` → `SplitView`, recursing → `PaneView` → `PaneBar`) walk
the tree and draw it. They hold no layout logic.

A pure `splitShortcuts({required bool isWindows})` decides which keys mean what,
in the same testable shape as the existing `shellCommand()` and
`ptyEnvironment()`.

### The insertion rule

Two rules, chosen by one comparison — does the focused pane's *parent split*
already run along the axis requested? The new pane always ends up adjacent to
the focused one; the only question is whether the tree deepens.

- **Same axis → insert as a sibling.** The new pane joins the parent's children
  immediately after the focused pane. The tree stays flat.
- **Different axis (or the focused pane is the root) → wrap.** The focused pane
  is replaced by a new `SplitNode` holding `[focused, new]`. The tree deepens by
  one level.

**Closing runs the rules backwards.** Remove the pane; if its parent split is
left with a single child, **dissolve that split and hoist the child into its
place**. Without that collapse the tree accumulates one-child splits that draw
nothing yet still hold ratios — invisible on screen, and exactly how this kind
of layout rots over a long session. It is also three lines to test and
impossible to catch by eye, which is the argument for this whole architecture in
miniature.

## Keyboard interception

In a terminal app, keystrokes belong to the terminal — every key is forwarded to
the pty. Split hotkeys must be taken before the terminal sees them, or they land
in Claude's prompt. `TerminalView.onKeyEvent` is consulted ahead of everything
else and swallows a key by returning `KeyEventResult.handled`. That is the
interception point.

## Testing

| Unit | Tested by |
|---|---|
| `Workspace` — split, close and reflow, resize, neighbour | unit tests, no engine |
| `splitShortcuts()` | unit tests |
| `Session` | constructor only; the wiring needs the app |
| `SplitView` / `PaneView` | by eye, running the app |

The line between rows two and three is the honest one. Everything above it can
be proven; everything below must be watched, on both platforms, as M0 was.

## Definition of done

Several sessions running at once in one window, split by hotkey into an
arbitrary arrangement, each pane titled by its own program and showing a spinner
while it works; dividers drag; focus moves by key and by click; a finished
session closes its pane and the last one quits the app — confirmed by hand on
both macOS and Windows.

## Deferred — not in Milestone 1

- Card-grid overview with per-agent status, last output line, diff counts
- Expand a card into a full terminal / collapse back to an overview
- Naming or renaming sessions by hand (M1 titles come from the program)
- Session lifecycle beyond create and close — no restart, no respawn
- Configurable spawned command per session
- Persisting a layout across restarts
- A "needs attention" signal (`Terminal.onBell` is the obvious later hook)

## Watch out

- The pty/terminal wiring is M0's, already proven on both platforms. Do not
  rewrite it while restructuring around it; `PtyTerminal` becomes `PaneView` by
  taking a session it is handed rather than spawning one, and little else should
  change inside it.
- The busy threshold is the one number only running the app will settle: too
  short and the icon flickers between output bursts, too long and it lags behind
  a finished task.
- Every hotkey must be confirmed not to reach the pty. A binding that both
  splits a pane *and* lands a character in Claude's prompt is worse than no
  binding at all.
- Resist putting layout logic in widgets when a tree operation proves awkward.
  That awkwardness is the design telling you the tree needs work, and moving the
  logic into a widget is how the testable line rises again.

# Orthanc — File Drop Design

## Goal

Let a file (or several) dragged in from Finder or Explorer be dropped onto a
pane, and have Orthanc write its path into that pane's pty as a bracketed
paste — `@`-prefixed when a program owns the pane, so Claude Code reads the
file and, for an image, loads it as image content rather than a filename; a
bare quoted path when the shell sits idle at its prompt.

## Why this, and why now

Today the only way to hand Claude Code a file is to type its path by hand, or
to paste an image from the OS clipboard — the latter being Claude Code
reaching into the OS clipboard itself, something Orthanc cannot imitate from
the pty side. There is no escape sequence by which a terminal emulator hands
image bytes to a CLI it hosts; the entire door is Claude Code's own
`@`-reference syntax, which loads an `@`-referenced image file as image
content, not text. A bare path written into the prompt is inert — Claude Code
does not read a file merely because its path appears. So "drop a file to give
the path" and "drop a file to let Claude take it as an image" are the same
feature, differing by one character.

## Decisions

1. **What text is written is inferred from the pane, not asked of the
   user.** `sessionPath(session.name.value)` — the same accessor `Copy Path`
   already uses — returning non-null means the shell's own title-on-prompt
   hook just announced a directory, so the pane sits idle at its prompt and
   the path is written bare and quoted. Null means a running program (most
   likely Claude Code) currently owns the title, so the path becomes an
   `@`-reference instead.

   This inference is wrong, on purpose, in three named and accepted ways:
   - **An unhooked shell** (PowerShell, fish) never announces a path, so
     every drop there reads as "program running" — deterministic, not
     occasional.
   - **A program other than Claude Code** (`vim`, `less`, a REPL) looks
     identical to it and receives the same `@`-reference.
   - **A freshly spawned pane, before its first prompt draws,** has an empty
     `name`, which also reads as "program running."

2. **The pane under the cursor receives the drop, not the focused one.**
   Resolved through the same `_fractionalPosition` + geometry
   `dropTargetAt` already gives pane-rearranging drags — a new
   `dropPaneAt` sibling discards the edge `side` that geometry also
   returns, since a file dropped near a pane's edge must land *in* that
   pane, never imply a split.

3. **Several files join one per line, except under `cmd.exe`, which joins
   with spaces.** `cmd.exe` has no bracketed paste of its own — at a bare
   `cmd` prompt a newline in pasted text runs as a pressed Enter, so a
   multi-file drop there would execute each line rather than sit in the
   buffer. The narrower fix (space-join only the bare-path branch, where
   the hazard lives) was widened to both of cmd's branches, since
   `@a.txt @b.txt` on one line costs nothing as a Claude Code input.

4. **A wrong-inference escape hatch is deferred.** Considered: a right-click
   menu item re-inserting the last dropped path in the other form. Argued
   down — see *Deferred*.

## Architecture

**`dropPaneAt(Workspace, double fx, double fy)`** (`lib/workspace_view.dart`,
beside `dropTargetAt`) — `dropTargetAt(...)?.id`, discarding the zone.

**`droppedPathsText`** (`lib/dropped_paths_text.dart`, new) — the pure
decision: given the dropped paths, whether the pane is `@`-referenced,
whether the platform is Windows, and whether the shell is `cmd.exe`, returns
the exact text to paste. Three quoting forms:

- **Bare path, POSIX shells** — single quotes, `'` escaped as `'\''`. Not
  double quotes: those still let the shell expand `$`, backtick, backslash
  and `!`, so a file named `$HOME (1).txt` would be mangled.
- **Bare path, `cmd.exe`** — double quotes, no escaping. NTFS forbids a
  literal `"` in a filename, so there is nothing to escape.
- **`@`-reference** — unquoted (`@'…'` would put the quote inside the
  filename token). A space is backslash-escaped on a POSIX-style path — the
  form macOS Terminal and iTerm already emit on a file drag — and left
  verbatim on a Windows path, where backslash is already the separator and
  escaping a space would be ambiguous.

**`isCmdShell(String executable)`** (`lib/shell_prompt_hook.dart`) — public,
replacing the inline `_baseName(executable) == 'cmd'` check `shellPromptHook`
already made, so one definition serves both the prompt-hook installation and
the drop-joining decision.

**`dropPathsInto(Session, List<String>, {required bool isWindows})`**
(`lib/session_drop.dart`, new) — the `Session`-facing verb, mirroring
`session_clipboard.dart`'s free-function shape: reads `sessionPath` and
`isCmdShell`, calls `droppedPathsText`, then `session.terminal.paste(text)`
and `terminalController.clearSelection()`. `isCmdShell`'s basename match is
gated by `isWindows` here too, matching `shellPromptHook`'s own use of the
same check — otherwise a POSIX binary named literally `cmd` would be
mistaken for `cmd.exe`. `isWindows` is a parameter, not read from
`Platform` internally, matching every other platform-dependent pure
decision in this codebase (`shellPromptHook`, `homeDirectory`, …) — the
caller (`WorkspaceView._onFileDrop`) reads `Platform.isWindows` once, at the
real I/O boundary.

**`WorkspaceView`** wraps `_boundsKey`'s `Container` in a `DropTarget`
(`desktop_drop`) — outside the `Container`, so the box `paneRects()` is
measured against is unchanged. `_onFileDrop` resolves the drop through
`_fractionalPosition` + `dropPaneAt`, focuses the landed pane (matching
`split`/`swap`'s own convention), and calls `dropPathsInto`.
`_onFileDragUpdated`/`_onFileDragExited` mirror the pane-drag hover
handlers' no-change early return, tracking `String? _fileDropHoverId`.

**`PaneView`** gains `isFileDropTarget` and paints a
`Colors.lightGreenAccent` overlay when set — a `Positioned.fill` →
`IgnorePointer` → `DecoratedBox`, the same "paint over, never resize" shape
`focusBorderKey`'s doc comment requires, factored out of `_dropHighlight`
into a shared `_dropFill`. **Deliberately not amber**: amber already means
"a pane will be swapped or moved here," and a file drop changes no layout at
all — wearing the layout-drag colour would say something untrue.

**`SplitView`** threads `fileDropHoverId` through `_shrinkablePane` and
`_childSplitView`, exactly as `dragHoverId` already is.

## The dependency

**`desktop_drop: ^0.8.4`** — Apache-2.0, verified publisher, actively
releasing. It supplies `DropDoneDetails.globalPosition` (the geometry) and
`DropItem.path` as a bare `String` (real paths — the App Sandbox is
deliberately off, so no `extraAppleBookmark` handling is needed).

Rejected: `super_drag_and_drop`, whose last stable release predates this by
over a year and which pulls `super_native_extensions` → a Rust toolchain, or
downloads precompiled native binaries from a third party at build time. For
a repo that pins two dependencies to personal forks with a page of
justification, that is the wrong shape of dependency.

**Cost, stated plainly:** this is the first non-trivial third-party *native*
runtime dependency Orthanc takes that it does not fork. Its native surface
(Swift on macOS, C++ on Windows) is small — roughly 200 lines — so the
contingency if it lapses is to vendor that surface directly into
`macos/Runner`/`windows/runner` rather than replace the package.

## Testing

| Unit | Tested by |
|---|---|
| `dropPaneAt` — pane-id-only, discards the edge zone `dropTargetAt` also returns, off-tree null | unit tests, no engine |
| `droppedPathsText` — every quoting/escaping/joining branch (11 cases) | unit tests |
| `dropPathsInto` — the inference, cmd space-joining vs newline elsewhere, empty no-op, selection cleared | widget tests |
| `isCmdShell` — cmd.exe by name and full path, false for bash/PowerShell | unit tests |
| `PaneView`'s file-drop highlight — appears/absent on the flag, **`TerminalView`'s measured size identical either way** (the reflow guard) | widget tests |
| `SplitView`'s `fileDropHoverId` — reaches only the named pane, not its sibling | widget tests |
| Drop lands in the correct quadrant and takes focus; divider-gutter and off-tree drops no-op; pane-bar swap/split drags unaffected; the hover glow follows the cursor and does not reflow a running full-screen program; a `.png` dropped on a live Claude Code pane loads as image content | by hand, both platforms |

## Definition of done

Dropping a file onto any pane writes its path into that pane's pty, quoted
correctly for the pane's shell and prefixed with `@` when a program owns the
pane; several files join one per line except under `cmd.exe`, which joins
with spaces; the pane under the cursor receives the drop and takes focus,
never the focused pane if it differs; a hover glows the pane it would land
in without ever reflowing the terminal beneath it; dropping on the gutter or
outside the tree is a silent no-op; and — the claim that earns the feature —
dropping an image onto a running Claude Code pane and pressing Enter makes
Claude describe the image, not recite its filename.

## Deferred — not in this change

- **A right-click "insert in the other form" escape hatch.** The cost is not
  the menu item but the per-pane "last dropped path" state behind it, whose
  staleness question — expire on focus change? on a pty write? never? — has
  no non-arbitrary answer. And the remedy's shape does not fit the
  failure's shape: under PowerShell the inference is wrong on *every* drop,
  forever, so a per-drop undo would be a tax paid on every use, not an
  escape hatch reached for occasionally. If real use shows the wrong form
  landing often enough to matter, the right remedy is a **Settings
  toggle** ("always insert `@` references") — a one-time decision matching
  a persistent condition.
- **`paneRects()` vs. the collapsed-pane layout.**
  `SplitView._buildCollapsedSplitChildren` shrinks a collapsed pane and
  redistributes the rest, so the fractional hit-test can disagree with the
  screen in a column holding one. The existing pane-rearrange drag already
  carries this bug; fix both hit-tests together later rather than fork the
  geometry now.
- **Vendoring `desktop_drop`'s native code**, should the package go
  unmaintained.

## Watch out

- `Session.executable` is the pane's *startup* executable — if the user
  runs another shell inside a `cmd` pane (or vice versa), `isCmdShell`'s
  answer goes stale. Accepted, not fixed.
- A program that owns a pane's title but never enabled bracketed paste
  (`less`, a plain REPL) receives a raw newline-joined paste, which will
  execute line by line exactly as a bare `cmd` prompt would. Only `cmd.exe`
  is special-cased; other unhooked programs are not.
- The `DropTarget` wraps `_boundsKey`'s `Container` from *outside* — the
  box `paneRects()` measures must stay exactly what it was before this
  feature, the same invariant the pane-rearrange design already names for
  its own bounding-box `GlobalKey`.
- `desktop_drop`'s `onDragUpdated`/`onDragExited` deliver `DropEventDetails`,
  not `DropDoneDetails` — different types, easy to conflate when wiring the
  three callbacks side by side.

## Unverified

**How Claude Code's `@`-parser terminates a path token, and whether it
honours a backslash-escaped space, was never confirmed by hand** — the
physical check (drop a space-bearing image onto a live Claude Code pane,
read what lands) needs a real drag gesture on a real desktop, which was
judged too invasive to script against a live session and left to whoever
runs this feature next. `_atPath`'s backslash-escaping is built on the
documented reasoning in *Architecture* above, not on an observed result.
If the escaped form fails in practice, the fix is narrow: drop the escaping
in `_atPath` for the POSIX branch too, update
`test/dropped_paths_text_test.dart`'s two affected cases, and record the
finding here.

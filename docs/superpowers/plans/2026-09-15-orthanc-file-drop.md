# File Drop Implementation Plan

**Goal:** Let a file dragged in from Finder or Explorer be dropped onto a
pane, writing its path into that pane's pty as a bracketed paste —
`@`-prefixed when a program owns the pane (so Claude Code reads the file,
and loads an image as image content), bare and quoted when the shell sits
idle at its prompt. See the paired design doc,
`2026-09-15-orthanc-file-drop-design.md`, for the full reasoning.

**Architecture:** `desktop_drop`'s `DropTarget` wraps `WorkspaceView`'s
existing `_boundsKey` bounding box from outside, reusing the same
`_fractionalPosition` conversion and a new pane-id-only `dropPaneAt`
sibling of `dropTargetAt`. The text itself is a pure decision
(`dropped_paths_text.dart`) fed by a `Session`-facing verb
(`session_drop.dart`) mirroring `session_clipboard.dart`'s shape. A hover
highlight in `PaneView` reuses the existing "paint over, never resize"
overlay discipline, in its own colour so it is never mistaken for the
pane-rearrange drag's amber.

**Tech Stack:** Flutter/Dart, `flutter_test`, `desktop_drop: ^0.8.4`.

## Global Constraints

- Match existing test style exactly: `group`/`test`, a named `expected`
  constant declared before the call, one assertion comparing against it.
- Pure decisions live in their own top-level-function file with their own
  test — `dropped_paths_text.dart` follows `shellCommand()`/`sessionPath()`'s
  shape, not a class.
- The `DropTarget` wraps `_boundsKey`'s `Container` from *outside* — the box
  `paneRects()` measures must stay exactly what it was before this feature.
- No new gesture handling in the `TerminalView`/`ClipRect`/`MouseRegion`
  region of `pane_view.dart` — the drop target is window-wide, not per-pane.
- The hover highlight must not change `TerminalView`'s measured size — prove
  it with a widget test, not by eye alone.

## Tasks

- [x] **Step 1 — a dropped file reaches the pane under the cursor.**
  Add `desktop_drop` to `pubspec.yaml`. Add `dropPaneAt` beside
  `dropTargetAt` in `lib/workspace_view.dart`. Wrap `_boundsKey`'s
  `Container` in a `DropTarget`; add `_onFileDrop` resolving through
  `_fractionalPosition` + `dropPaneAt`, focusing the landed pane, and (this
  step only) pasting the first file's raw path. Tests in
  `test/workspace_view_dropzone_test.dart`.

- [x] **Step 2 — the text is right: quoting, `@`, joining.** New
  `lib/dropped_paths_text.dart` (the pure decision) and its test. New
  `lib/session_drop.dart` (`dropPathsInto`, mirroring
  `session_clipboard.dart`) and its test. New public `isCmdShell` in
  `lib/shell_prompt_hook.dart`, replacing the inline basename check, with
  its own tests. `_onFileDrop` now calls `dropPathsInto`.

- [x] **Step 3 — hover highlight.** `PaneView` gains `isFileDropTarget` and
  a `lightGreenAccent` overlay, factored out of `_dropHighlight` into a
  shared `_dropFill`. `SplitView` threads `fileDropHoverId` through.
  `WorkspaceView` tracks `_fileDropHoverId` via `onDragUpdated`/
  `onDragExited`, mirroring the pane-drag hover handlers' no-change early
  return. Widget tests include the reflow guard: `TerminalView`'s measured
  size is asserted identical with the flag set and clear.

- [x] **Step 4 — documentation.** This plan; the paired design doc;
  `CHANGELOG.md`; `README.md`.

## Verification

`flutter analyze` clean and the full `flutter test` suite green at the close
of every step (521 tests at the close of Step 3, up from 491 at the start).
`flutter build macos --debug` succeeds and the built app launches. Physical
checks — the drag lands on the correct pane quadrant, the hover glow follows
the cursor without reflowing a running program, a `.png` dropped on a live
Claude Code pane loads as image content, `cmd.exe`'s space-joined multi-file
drop does not execute — are the operator's to run by hand; see the design
doc's *Unverified* section for the one open question (the `@`-parser's
handling of a space) that only that hand check can close.

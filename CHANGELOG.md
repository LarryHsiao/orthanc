# Changelog

All notable changes to Orthanc are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

Releases before 1.1.18 are not recorded here; their notes are generated from
commit messages on each [GitHub Release](https://github.com/LarryHsiao/orthanc/releases).

## [Unreleased]

### Added

- Copy a file in Finder or Explorer, then paste it into a pane — right-click
  Paste, Windows' `Ctrl+Shift+V`, or macOS's `Cmd+V` — and its real path
  lands the same way a drop would: `@`-referenced when a program owns the
  pane, bare-quoted when the shell sits idle. A copied web link is never
  mistaken for a file. Ordinary text still pastes as text, unchanged.
- Drag a file onto a pane to write its path into that pane's terminal — an
  `@`-reference when a running program (Claude Code, most likely) owns the
  pane, so an image drops in as image content rather than a filename;
  a bare quoted path when the shell sits idle at its prompt. Several files
  join one per line, except under `cmd.exe`, which has no bracketed paste
  of its own and joins with spaces instead so a multi-file drop can't run
  each line as a command. The pane under the cursor receives the drop and
  takes focus, and glows while hovered. Under PowerShell or fish — shells
  Orthanc has no title-on-prompt hook for — every drop is read as "a
  program owns this pane," since there is no announced prompt to tell the
  two cases apart.
- A `Copy Path` item in the right-click menu, copying a pane's current
  working directory — fed by the same shell prompt hook that already names
  it in the pane bar, so it is live under bash, zsh and `cmd.exe`, and
  greyed out under a shell the hook does not cover (PowerShell, say).
- `Ctrl+Shift+C` and `Ctrl+Shift+V` on Windows, bound directly by Orthanc
  ahead of the terminal engine, to copy the selection and paste.

### Fixed

- Keyboard copy and paste on Windows, unreliable through the terminal
  engine's own keyboard handling since the right-click Copy/Paste menu was
  added as a workaround for exactly this (see the `8771b58` commit that
  introduced it).

## [1.4.2] - 2026-08-22

### Fixed

- A stale native handoff plugin (`flutter_pty`'s Windows library missing a
  symbol its Dart bindings called) could throw before the window was ever
  shown, leaving the process running with no visible window. The failing
  call is now guarded — a mismatch there degrades cross-instance handoff
  instead of hiding the whole app.

## [1.4.1] - 2026-08-20

### Changed

- Cross-instance pane handoff — dragging a pane out of the window to another
  running Orthanc instance — is now explicitly disabled on Windows; the
  drag just cancels, the same as dropping on the divider gutter. macOS is
  unaffected.

## [1.4.0] - 2026-08-19

### Added

- Quake mode can now be set to start automatically at login. A checkbox in
  Settings registers the app as a login item — a `Run` registry value on
  Windows, a `launchd` agent on macOS — so a fresh boot has quake mode ready
  without opening it by hand first. Off by default.

## [1.3.0] - 2026-08-19

### Added

- A pane can now be dragged out of its window entirely and handed off to
  another running Orthanc instance — the live session, process and all,
  survives the move with no restart. The pane currently lands on the
  target window's focused pane rather than the exact drop point, and
  scrollback isn't carried across yet; both are planned. macOS only for
  now — Windows support is still in progress.

## [1.2.0] - 2026-08-18

### Added

- Panes can now be rearranged by dragging a pane's title label. Dropping
  onto another pane's centre swaps the two sessions in place, sizes staying
  with their slots. Dropping onto one of its edges instead lifts the
  dragged pane out and re-splices it in on that side — reordering within
  the same row or column, or splitting a new one, as the layout calls for.

## [1.1.18] - 2026-08-17

### Fixed

- A column holding a collapsed pane no longer leaves an empty strip along its
  bottom edge. The collapsed layout draws no dividers, yet was still reserving
  their space — four logical pixels per divider, so the gap grew with every
  split in that column.
- A column can no longer be reduced to nothing but pane bars over dead space.
  The last expanded pane in a column refuses to collapse, and closing a pane
  releases the collapse of any column it would have emptied.

[1.4.2]: https://github.com/LarryHsiao/orthanc/releases/tag/v1.4.2
[1.4.1]: https://github.com/LarryHsiao/orthanc/releases/tag/v1.4.1
[1.4.0]: https://github.com/LarryHsiao/orthanc/releases/tag/v1.4.0
[1.3.0]: https://github.com/LarryHsiao/orthanc/releases/tag/v1.3.0
[1.2.0]: https://github.com/LarryHsiao/orthanc/releases/tag/v1.2.0
[1.1.18]: https://github.com/LarryHsiao/orthanc/releases/tag/v1.1.18

# Orthanc — Milestone 0 Design

## Naming

**Orthanc** — Saruman's tower and the seat of a palantír: one vantage watching
and directing many remote things. Matches the existing Tolkien-themed tool
naming (skadi).

## Goal

One Claude Code session, launched from a Flutter desktop window, rendering
and accepting input correctly on both macOS and Windows. Nothing past that
is in scope for Milestone 0.

## Guiding principle

Kill the pty risk first. `forkpty` (macOS) and ConPTY (Windows) are the only
parts of this project with real cross-platform danger. Once one Claude Code
session renders and takes input correctly on both platforms, everything else
is ordinary Flutter UI work. No dashboard, card grid, or multi-session logic
starts before Milestone 0 passes on both platforms.

## Stack

- Flutter desktop (macOS + Windows targets)
- `flutter_pty` (v0.4.2) — pty spawn, unified Unix pty / Windows ConPTY API:
  `Pty.start(...)`, `pty.output` (stream), `pty.write(...)`,
  `pty.resize(rows, cols)`, `pty.kill()`
- `xterm` (xterm.dart, v4.0.0) — terminal emulator: parses ANSI escapes,
  renders the grid, handles keyboard input; pairs with `flutter_pty`

Both packages are published by verified publisher `terminal.studio`, both
support macOS + Windows (ConPTY), and their documented API surface matches
what this design relies on. Neither has published an update in 18mo–2yr —
not a blocker, but worth knowing going in.

## Platforms

macOS + Windows. Linux is dropped for now.

## Spawned command

Hardcoded to `claude` for Milestone 0. Generalizing to "any command, not
just Claude Code" is explicitly deferred — see Deferred, below.

## Steps

1. **Project scaffold** — `flutter create` a new desktop project; enable
   macOS + Windows desktop targets. Add `flutter_pty` and `xterm` to
   pubspec.
   **Verify:** empty window builds and runs on macOS.

2. **Spawn a shell (not Claude yet)** — wire `flutter_pty` + `xterm`: start
   a plain shell (`zsh`/`bash` on macOS, `powershell`/`cmd` on Windows),
   pipe `pty.output` into the terminal, forward input to `pty.write`. Handle
   resize via `pty.resize(rows, cols)`.
   **Verify:** `ls`/`dir`, arrow keys, clear-screen behave, no garbled
   escapes.

3. **Spawn Claude Code** — swap the spawned command for the `claude`
   executable (hardcoded, not configurable yet). Resolve its path
   per-platform — the app won't inherit an interactive shell's PATH.
   **Verify:** the Claude Code TUI renders correctly, prompts accept input,
   streaming output and redraws look right.

4. **Cross-platform pass** — build and run the identical thing on Windows.
   Expect ConPTY escape-sequence quirks against a heavy TUI like Claude
   Code — budget real time here; this is where the actual risk lives.
   **Verify:** Milestone 0 behaves the same on Windows as on macOS.

## Definition of done

One Claude Code session, launched from the Flutter app, rendering and
accepting input correctly on both macOS and Windows. When true, the pty
risk is retired and the rest of the project becomes pure Flutter UI work.

## Deferred — do not start until M0 passes

- Multiple concurrent sessions
- Card-grid overview with per-agent status (running/waiting/done), last
  output line, diff counts
- Expand a card into a full terminal / collapse back to overview
- Session lifecycle: create, name, kill, restart
- Configurable spawned command per session (beyond `claude` — running other
  CLI agents, not just Claude Code)
- Layout, resizing, window-management polish

## Watch out

- Don't scope-creep M0 into any Deferred item above, even though it's
  tempting once the terminal renders — the dashboard/multi-session work is
  explicitly gated behind M0 passing on *both* platforms.
- Step 4 (Windows/ConPTY) is the real risk. Budget for it; don't treat it as
  a formality after macOS works.
- The command is intentionally hardcoded to `claude` in Step 3 — don't
  "improve" this into a config value inside M0; that's a Deferred item
  chosen to defer, not an oversight.

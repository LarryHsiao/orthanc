# Orthanc

A Flutter desktop app that spawns a [Claude Code](https://claude.com/claude-code)
session inside an embedded terminal — one window watching and directing a
running agent, the way its namesake tower watches over Middle-earth through a
palantír.

## Status: Milestone 1 (code complete, awaiting its cross-platform walk)

Milestone 1 makes one window hold many sessions at once as tmux-style split panes,
arranged by hotkey. All eleven of its code tasks are built, reviewed and committed;
`flutter test` runs 63 green and the app builds and launches on Windows. **It has not
yet been walked by hand on either platform**, so the milestone is not done — Milestone
0 taught that lesson with three defects found only by running the thing. See
[`docs/superpowers/specs/2026-07-21-orthanc-milestone-1-design.md`](docs/superpowers/specs/2026-07-21-orthanc-milestone-1-design.md)
for the design, and the *State as of 2026-07-21* section of
[`docs/superpowers/plans/2026-07-21-orthanc-milestone-1.md`](docs/superpowers/plans/2026-07-21-orthanc-milestone-1.md)
for what remains, the known debt, and what to watch during the walk.

## Milestone 0 (complete)

Milestone 0's only goal: one Claude Code session, launched from this app,
rendering and accepting input correctly on both macOS and Windows. Nothing
past that is in scope yet — no multi-session dashboard, no session lifecycle
management, no configurable spawned command. See
[`docs/superpowers/specs/2026-07-20-orthanc-milestone-0-design.md`](docs/superpowers/specs/2026-07-20-orthanc-milestone-0-design.md)
for the full design and
[`docs/superpowers/plans/2026-07-20-orthanc-milestone-0.md`](docs/superpowers/plans/2026-07-20-orthanc-milestone-0.md)
for the implementation plan.

The app scaffolds on macOS + Windows and spawns a real interactive shell in an
embedded terminal, from which `claude` starts and runs — confirmed by hand on
both platforms. Milestone 0's definition of done is met; everything from here
(multi-session, card-grid overview, session lifecycle, configurable commands)
is ordinary Flutter UI work.

The Windows pass turned up three defects, none of them in ConPTY — the risk the
plan actually feared. The pty layer, rendering, resizing and escape handling all
worked on the first build. What did not:

1. **An `xterm` SGR parser bug** (found earlier, on macOS) — private-marker CSI
   sequences ending in `m` were misread as text styles, underlining the session.
2. **A missing `viewId`** in `xterm`'s text input configuration. Flutter's
   Windows embedder rejects `TextInput.setClient` without it, so the connection
   never attached and every printable character was dropped — while Enter and
   the arrow keys still worked, since those take a different path. macOS
   tolerates the omission via its implicit view.
3. **A POSIX-shaped environment allowlist.** `flutter_pty` builds the child's
   environment from scratch, copying only `LOGNAME`/`USER`/`DISPLAY`/`LC_TYPE`/
   `HOME`/`PATH`. On Windows that omits `SystemRoot`, without which a spawned
   executable loads no system DLLs and dies silently — `claude` was found,
   launched, and gone, with an empty stderr to show for it. See
   `lib/pty_environment.dart`.

The first two are fixed in the pinned `xterm` fork and proposed upstream
([#230](https://github.com/TerminalStudio/xterm.dart/pull/230),
[#231](https://github.com/TerminalStudio/xterm.dart/pull/231)); the third is
fixed here.

One note for anyone who sees a colorless TUI: Orthanc forwards the environment
on Windows, `NO_COLOR` included. If the parent process sets it — Claude Code
does, for its own subprocesses — the spawned `claude` will honor it. That is
inheritance working correctly, not a bug.

## How it works

- [`flutter_pty`](https://pub.dev/packages/flutter_pty) spawns a process
  behind a pseudo-terminal (`forkpty` on macOS, ConPTY on Windows) and streams
  its raw output.
- [`xterm`](https://pub.dev/packages/xterm) (xterm.dart) parses that output as
  a real terminal — ANSI escapes, cursor positioning, resizing — and renders
  it, forwarding keyboard input back to the spawned process.
- `lib/pty_terminal.dart` wires the two together into one `PtyTerminal`
  widget; `lib/claude_command.dart` resolves the `claude` executable's
  absolute path per-platform, since a GUI app launched outside a shell doesn't
  inherit an interactive shell's `PATH`; `lib/pty_environment.dart` decides
  what environment the spawned process gets, which differs per platform for
  the reason given under Status.

## Running it

```bash
flutter pub get
flutter run -d macos    # or: -d windows
```

**macOS note:** this app spawns arbitrary child processes (the whole point),
which macOS App Sandbox forbids — sandboxing is disabled in
`macos/Runner/*.entitlements` for exactly this reason. That rules out Mac App
Store distribution while sandboxed; direct/notarized distribution (the
standard path for terminal-emulator-style developer tools) is unaffected.

## Tests

```bash
flutter test
```

Pure logic (shell/executable resolution) is unit-tested directly. The
pty/terminal wiring itself can only be judged by actually running the app —
see the plan's Global Constraints for why `flutter test`'s harness can't
exercise it.

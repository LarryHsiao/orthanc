# Orthanc

A Flutter desktop app that spawns a [Claude Code](https://claude.com/claude-code)
session inside an embedded terminal — one window watching and directing a
running agent, the way its namesake tower watches over Middle-earth through a
palantír.

## Status: Milestone 0 (in progress)

Milestone 0's only goal: one Claude Code session, launched from this app,
rendering and accepting input correctly on both macOS and Windows. Nothing
past that is in scope yet — no multi-session dashboard, no session lifecycle
management, no configurable spawned command. See
[`docs/superpowers/specs/2026-07-20-orthanc-milestone-0-design.md`](docs/superpowers/specs/2026-07-20-orthanc-milestone-0-design.md)
for the full design and
[`docs/superpowers/plans/2026-07-20-orthanc-milestone-0.md`](docs/superpowers/plans/2026-07-20-orthanc-milestone-0.md)
for the implementation plan.

Done so far: the app scaffolds on macOS + Windows, spawns a real interactive
shell in an embedded terminal, and spawns `claude` in its place — confirmed
working on macOS. The Windows pass (verifying the same behavior against
ConPTY) is the one remaining step before Milestone 0 is complete.

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
  inherit an interactive shell's `PATH`.

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

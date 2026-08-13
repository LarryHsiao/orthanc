# Orthanc

A Flutter desktop app for **Windows and macOS** that holds several embedded
terminals in one window — split by hotkey, each running its own shell, so a
handful of [Claude Code](https://claude.com/claude-code) sessions can be watched
and directed side by side, the way its namesake tower watches over Middle-earth
through a palantír.

To be exact about what it does on launch: **each pane starts a shell**, not
`claude` itself. You type `claude` in the pane, as you would in any terminal.
The shell is chosen per platform by default and can be changed in Settings.
Linux is not supported.

## Status: shipping

Four tagged releases stand, `v1.0.0` through `v1.1.1`, built and published for
both platforms. Milestones 0 and 1 are complete and walked by hand on macOS and
Windows alike. `flutter test` runs 262 green.

Everything since Milestone 1 has been ordinary feature work. Most of it carries
its own design spec and implementation plan under `docs/superpowers/`: pane
titles, pane collapse, pane rename, a configurable startup executable, OSC 8
terminal hyperlinks, terminal appearance settings (color scheme and font), and
a second OS window on both platforms. A few smaller pieces — the focused-pane
border and the pending-attention marker — shipped without a design doc of
their own, in the same shape as the ones that came before them.

## What it does

- **Many sessions in one window**, as tmux-style split panes arranged by hotkey.
  The layout is an immutable tree; splitting, closing and moving focus each
  return a new one.
- **Pane titles that follow the program.** A session's bar shows what the
  running program last announced (Claude Code sets its title via OSC 0) beside
  its current activity. `bash` and `zsh` get a title-on-prompt hook installed so
  their panes name themselves too; any other shell is left alone.
- **Collapse and rename.** A pane can be folded down to its bar alone and
  restored, and can carry a manual name the running program cannot overwrite.
- **A configurable startup executable.** The shell each session spawns is
  detected per platform by default and can be overridden in Settings
  (`Cmd+,` on macOS, or the title-bar menu on Windows); the path is validated
  before it is saved and persists to a JSON file under application support.
- **Terminal appearance settings.** Color scheme and font family/size are
  picked in the same Settings dialog, with a live preview, and apply to every
  open pane immediately on Save.
- **Clickable hyperlinks.** OSC 8 links emitted by a program render underlined
  and open on `Cmd`/`Ctrl`+click — `http` and `https` only, since OSC 8 lets a
  program claim any scheme and launching those from untrusted terminal output is
  a real risk. Other schemes still underline; they simply do nothing.
- **A focus you can see.** The focused pane carries a dimmed accent border and
  bar; a pane that finishes a burst of activity while unfocused picks up a
  tertiary top-edge stripe until it is looked at, content-blind by design — it
  reacts to how often the title changes, never to what it says.
- **A second window.** `Cmd+N` (macOS) or `Ctrl+N` (Windows) opens another OS
  window with its own independent workspace and pty sessions, sharing the same
  persisted settings as the first.
- **A quake-style drop-down terminal.** The **Quake Window** menu item starts
  a dedicated instance that answers `` Ctrl+` `` from anywhere — snapped to
  the top edge of whichever screen the cursor is on, full width, half height
  by default or the last size it was resized to. Picking the menu item again
  summons the existing instance instead of opening a second one. Typing
  `exit` in its last pane hides the window rather than ending the process, so
  the hotkey survives it. macOS slides the window down, borderless — no
  title bar or traffic lights, so `Cmd+Q` is what ends the instance and
  releases the hotkey there — and hides it fully between summons, Dock icon
  intact. Windows shows/hides instantly, keeps its title bar (its close
  button ends the instance), and minimizes rather than hides, so the taskbar
  button survives too — there is no Windows slide, since the window's content
  is a swap-chain-backed surface `AnimateWindow` cannot capture.
- **Copy and Paste from a right-click menu.** Copy (enabled only with an
  active selection) and Paste, reachable by gesture rather than a shell
  convention — the reliable path on every platform, keyboard shortcuts aside.

### Key bindings

Each platform wears the scheme of the terminal already in use there — iTerm2 on
macOS, Windows Terminal on Windows.

|                     | macOS               | Windows        |
| ------------------- | ------------------- | -------------- |
| Split side by side  | `Cmd+D`             | `Alt+Shift+=`  |
| Split stacked       | `Cmd+Shift+D`       | `Alt+Shift+-`  |
| Move focus          | `Cmd+Alt+Arrow`     | `Alt+Arrow`    |
| Close pane          | `Cmd+W`             | `Ctrl+Shift+W` |
| Collapse / expand   | `Cmd+Shift+Enter`   | `Alt+Shift+Z`  |
| Open hyperlink      | `Cmd`+click         | `Ctrl`+click   |
| New window          | `Cmd+N`             | `Ctrl+N`       |
| Toggle quake window | `` Ctrl+` ``        | `` Ctrl+` ``   |

Every binding demands exactly its own modifiers and no others; anything not
listed reaches the terminal untouched. `Ctrl+D` is bound on neither platform: it
is EOF, and would kill a session rather than split one. The quake toggle is the
one row here that is not scoped to Orthanc: it is a system-wide hotkey,
claimed only while a quake instance runs, and consumed globally — including
inside the quake window's own terminal.

## How it works

- [`flutter_pty`](https://pub.dev/packages/flutter_pty) spawns a process behind
  a pseudo-terminal (`forkpty` on macOS, ConPTY on Windows) and streams its raw
  output.
- [`xterm`](https://pub.dev/packages/xterm) (xterm.dart) parses that output as a
  real terminal — ANSI escapes, cursor positioning, resizing — and renders it,
  forwarding keyboard input back to the spawned process.

Around those two:

- `lib/session.dart` — one `Session` owns a pty, its `Terminal`, its focus node
  and its title notifiers. It outlives the widget that draws it, so a collapsed
  pane keeps running.
- `lib/pane_view.dart` — one pane: its bar, and the terminal beneath.
- `lib/workspace.dart`, `lib/layout_node.dart` — the immutable layout tree and
  the operations over it (split, close, focus, collapse, find a neighbour).
- `lib/split_view.dart`, `lib/workspace_view.dart` — render that tree, and
  intercept key presses ahead of the terminal.

Eight files hold pure decisions with no I/O, which is why they carry the bulk of
the tests:

- `lib/shell_command.dart` — resolves the shell's absolute path per platform,
  since a GUI app launched outside a shell does not inherit an interactive
  shell's `PATH`.
- `lib/pty_environment.dart` — what environment the spawned process gets, which
  differs per platform for the reason given under *History*.
- `lib/home_directory.dart` — where a pane starts and where its rc files live.
  Windows never sets `HOME`, so this prefers it only when it names a path
  Windows can actually use, and falls back to `USERPROFILE`.
- `lib/split_shortcuts.dart` — what a key press means to the layout, or null to
  let the terminal have it.
- `lib/hyperlink.dart` — which modifier opens a link, and which URI schemes are
  safe to launch.
- `lib/shell_prompt_hook.dart` — which shell an executable names, and the
  title-on-prompt hook to feed it.
- `lib/new_instance.dart` — the command that starts another instance of this
  app, per platform; the caller spawns it detached.
- `lib/quake_geometry.dart` — the quake window's frame for a given screen and
  a possibly-saved size: full width and half height by default, clamped to
  the screen, snapped to its top edge.

## Prerequisites

Built and tested against **Flutter 3.38.7 (stable), Dart 3.10.7**. Nothing in
the repo pins the version, so if you hit an SDK error that is the first thing to
check; `pubspec.yaml` requires Dart `^3.10.7` at minimum.

- **Windows** — Visual Studio 2022 with the *"Desktop development with C++"*
  workload. Flutter's Windows target builds native C++; the workload is not
  optional, and Build Tools alone will not do.
- **macOS** — Xcode with its command-line tools.
- **Both** — run `flutter doctor` first and clear anything it flags for your
  platform. Android and web toolchains are irrelevant here.

## Running it

```bash
flutter pub get
flutter run -d windows   # or: -d macos
```

The first build pulls two git-pinned forks (see *The pinned dependencies*) and
compiles native code, so expect it to be slow; later builds are quick.

## Developing

```bash
flutter analyze                      # expected: no issues
flutter test                         # the whole suite
flutter test test/workspace_test.dart   # one file
```

Pure decisions live in their own files with their own tests — that is the
convention to follow when adding behaviour, and why the suite is as large as it
is relative to the app. Anything touching a pty or a real terminal cannot be
covered there and has to be walked by hand.

**macOS note:** this app spawns arbitrary child processes (the whole point),
which macOS App Sandbox forbids — sandboxing is disabled in
`macos/Runner/*.entitlements` for exactly this reason. That rules out Mac App
Store distribution while sandboxed; direct/notarized distribution (the standard
path for terminal-emulator-style developer tools) is unaffected.

**On color:** Orthanc forwards the whole environment to a pane on Windows, but
withholds `NO_COLOR` along with `TERM` and `LANG`. Earlier versions passed it
through, so a pane opened from a parent that sets it — Claude Code does, for its
own subprocesses — came up colorless. That was never a deliberate policy: macOS
panes never saw `NO_COLOR` at all, since flutter_pty builds their environment
from a short allowlist that omits it. Windows now matches. A program inside a
pane that wants no color can still set `NO_COLOR` for itself.

## Tests

```bash
flutter test
```

262 tests across 25 files. The pure decisions above are unit-tested directly,
along with the layout tree, title composition, and settings validation and
(de)serialization; the pane bar and the settings dialog carry widget tests. The
pty/terminal wiring itself can only be judged by actually running the app — see
the Milestone 0 plan's *Global Constraints* for why `flutter test`'s harness
cannot exercise it.

## Building a release

There is no CI workflow in this repository; the scripts below are written to run
either by hand or on an unattended runner configured elsewhere.

Each script fails on the first missing tool rather than part-way through, so
check its prerequisites before the first run.

Orthanc also checks for updates on launch and downloads them automatically via
Sparkle/WinSparkle — Sparkle shows its own one-time "install now?" consent
alert before applying — see [`docs/releasing.md`](docs/releasing.md) for the
one extra step this adds to the flow below: signing each artifact and
publishing it to the `appcast.xml` feed.

- **Windows** — `scripts/build_windows.ps1` builds a signed installer (via
  `installer/orthanc.iss`) and a raw zip. *Needs:* **Inno Setup 6** (`ISCC.exe`
  at its default path or on `PATH`), the **Windows SDK** (`signtool.exe` on
  `PATH`), and a code-signing certificate supplied through environment
  variables. `scripts/release_github.ps1` then uploads the artifacts to a GitHub
  Release — *needs* the `gh` CLI, authenticated — and skips silently unless the
  build sits on a `v*` tag.
- **macOS** — `scripts/publish_macos.sh` builds a signed, notarized DMG
  interactively. *Needs:* a **"Developer ID Application"** identity in the login
  keychain, Apple ID plus app-specific password for notarization, and `gh` for
  `--publish`. `scripts/ci_build_macos_dmg.sh` does the same unattended, taking
  the certificate and credentials from environment variables and building its
  own temporary keychain.

**None of this is needed to run or develop the app** — only to cut a release.
- **Icons** — `scripts/generate_app_icon.py` draws the app icon and writes every
  size both platforms consume, in place. It *is* the artwork's source; no vector
  file stands behind it. Requires Pillow.

## The pinned dependencies

`pubspec.yaml` overrides `xterm` and `flutter_pty` with forks, against four
defects. Each is documented in full beside its override.

1. **`xterm` misread private-marker SGR.** `CSI > Ps ; Ps m` — a keyboard-mode
   control, not a text style — was parsed as SGR, underlining the whole session.
   Proposed upstream as
   [#230](https://github.com/TerminalStudio/xterm.dart/pull/230).
2. **`xterm` omitted `viewId`** from its `TextInputConfiguration`. Flutter's
   Windows embedder rejects `TextInput.setClient` without it, so typing was dead
   on Windows. Proposed upstream as
   [#231](https://github.com/TerminalStudio/xterm.dart/pull/231).
3. **`xterm` dropped OSC 8 entirely** — only OSC 0/1/2 were special-cased, and
   hyperlinks fell through to `unknownOSC()`. The fork adds
   `Terminal.hyperlinkAt()` and a dedicated cell flag. Not filed upstream.
4. **`flutter_pty` did not quote its Windows command line.** Executable and
   arguments were joined into one string unquoted, so anything under a
   space-bearing path — Git for Windows' `C:\Program Files\Git\bin\bash.exe`
   among them — was misparsed by the child. It also wrote the executable twice.
   Not filed upstream.

## License

MIT — see [`LICENSE`](LICENSE). The pinned forks of `xterm` and `flutter_pty`
carry their own upstream licenses.

## History

### Milestone 0 — one session, both platforms

Milestone 0's only goal: one Claude Code session, launched from this app,
rendering and accepting input correctly on both macOS and Windows. See
[`docs/superpowers/specs/2026-07-20-orthanc-milestone-0-design.md`](docs/superpowers/specs/2026-07-20-orthanc-milestone-0-design.md)
for the design and
[`docs/superpowers/plans/2026-07-20-orthanc-milestone-0.md`](docs/superpowers/plans/2026-07-20-orthanc-milestone-0.md)
for the plan.

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

The first two are fixed in the pinned `xterm` fork and proposed upstream; the
third is fixed here.

### Milestone 1 — many sessions as split panes

Milestone 1 made one window hold many sessions at once as tmux-style split
panes, arranged by hotkey — twelve tasks, of which the last was the manual
cross-platform walk. See
[`docs/superpowers/specs/2026-07-21-orthanc-milestone-1-design.md`](docs/superpowers/specs/2026-07-21-orthanc-milestone-1-design.md)
for the design and
[`docs/superpowers/plans/2026-07-21-orthanc-milestone-1.md`](docs/superpowers/plans/2026-07-21-orthanc-milestone-1.md)
for the plan, whose *State as of 2026-07-21* section records what the reviews
caught that the plan got wrong — including a `Session.dispose()` race against
its own pty, on the main path rather than a corner.

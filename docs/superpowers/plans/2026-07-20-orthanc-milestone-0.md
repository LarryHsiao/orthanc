# Orthanc Milestone 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get one Claude Code session, launched from a Flutter desktop window, rendering and accepting input correctly on both macOS and Windows.

**Architecture:** A single Flutter desktop app (macOS + Windows) with one screen: a `PtyTerminal` widget that spawns a process via `flutter_pty` and renders it through `xterm.dart`'s `TerminalView`. The command the app spawns changes across tasks — a plain shell first (Task 2), then the `claude` executable (Task 3) — but the pty/terminal wiring itself does not change. Two small pure-function modules (`shell_command.dart`, `claude_command.dart`) decide *which* command to run per platform; they carry the only logic in this plan that unit tests can reach directly, since pty/terminal behavior itself can only be judged by running the app.

**Tech Stack:** Flutter (desktop, macOS + Windows), `flutter_pty` 0.4.2, `xterm` (xterm.dart) 4.0.0, Dart's built-in `test`/`flutter_test`.

## Global Constraints

- Platforms: macOS and Windows only. Linux is not a target for this plan.
- `flutter_pty: ^0.4.2` — verified current on pub.dev, published by `terminal.studio`.
- `xterm: ^4.0.0` — verified current on pub.dev, published by `terminal.studio`.
- Project/package name: `orthanc`.
- ~~The spawned command in Task 3 onward is hardcoded to `claude`.~~ **Reversed 2026-07-20, user's call:** `main.dart` now spawns `shellCommand()` (a plain shell) by default, not `resolveClaudeCommand()`. The user starts a Claude Code session themselves by typing `claude` inside that shell — `flutter_pty` already forwards a real `PATH`, so this works exactly like a normal terminal, and is arguably a better fit than auto-launching a session the instant the window opens. `lib/claude_command.dart`/`resolveClaudeCommand()` and its tests stay on disk, unwired, the same way `shell_command.dart` was left after Task 3 originally swapped away from it — not deleted, available if auto-launch is wanted again later. This does NOT retroactively change what Task 3 built or verified (spawning `claude` directly does still work, and was confirmed rendering correctly); it changes what `main.dart` defaults to.
- The spawned command still must not grow a config field, flag, or settings UI — that generalization (letting the user configure *which* command runs, beyond this one default-behavior toggle) is still explicitly deferred past Milestone 0.
- Do not build any of: multiple concurrent sessions, card-grid overview, session lifecycle (create/name/kill/restart), layout/window-management polish. All deferred past M0.
- ~~This machine (darwin) cannot run or verify the Windows target itself — Task 4 requires a separate Windows machine or VM. Flag this rather than skipping it silently.~~ **Resolved 2026-07-20:** Task 4 was run on a Windows 11 machine and passed. See Task 4 for what it found.
- **macOS App Sandbox must be disabled.** Discovered during Task 2's manual verification: Task 1's `flutter create` scaffolds `macos/Runner/DebugProfile.entitlements` and `Release.entitlements` with `com.apple.security.app-sandbox: true`, which blocks `Pty.start()` from fork/exec-ing any child process at all — the app's core feature cannot function while sandboxed. Confirmed against the `xterm` package's own bundled macOS example, which ships without this entitlement. User-approved: remove `com.apple.security.app-sandbox` (or set it `false`) from both entitlements files. This does forgo Mac App Store eligibility while sandboxed; direct/notarized distribution is unaffected and is the standard path for terminal-emulator-style tools.
- **`test/widget_test.dart` (from Task 1) is deleted, not carried forward.** Once `PtyTerminal` is wired into `OrthancApp` (Task 2 onward), `OrthancApp`'s tree always embeds a live pty-spawning widget. `flutter test`'s widget-test harness runs on a bare Dart VM with no Flutter engine embedder, so `flutter_pty`'s native library can never load there — any test that mounts `OrthancApp` via `pumpWidget` will crash, independent of the sandbox setting. This is the same reasoning already applied to `PtyTerminal`'s own test (constructor-only, no `pumpWidget`) — it now also forecloses widget-testing `OrthancApp`. User-approved: delete the file rather than attempt to preserve it.
- **`xterm` is pinned to a fork via `dependency_overrides`, not plain pub.dev `^4.0.0`.** Discovered after Task 3, during manual use: Claude Code's TUI rendered every line underlined (including box-drawing borders) in Orthanc but not in a real terminal (iTerm2). Root-caused by feeding Claude Code's actual captured output bytes through an unmodified `xterm` 4.0.0 `Terminal` directly (no Orthanc/flutter_pty involved) and reproducing the same corruption: `xterm.dart`'s escape parser dispatches any CSI sequence ending in `m` to its SGR (text-style) handler purely by final byte, without checking for a private-marker prefix (`<`, `=`, `>`, `?`). Claude Code sends `CSI > 4 ; 2 m` (xterm's `modifyOtherKeys` keyboard-mode control, unrelated to text style) very early in the session; the parser read its params `4` and `2` as plain SGR codes (underline, faint), and since nothing ever explicitly resets it, that bogus style sticks for everything drawn afterward. Fixed in a fork ([LarryHsiao/xterm.dart](https://github.com/LarryHsiao/xterm.dart), branch `orthanc-sgr-private-marker-fix`, pinned at commit `c63f583`) — `_csiHandleSgr()` now routes a private-marker-prefixed sequence to `unknownCSI()` instead of SGR. An Opus-model adversarial review of the first version of this fix (commit `ada2f61`) found the guard was two bytes too broad — `_csi.prefix` also captures `:`/`;` (same consumption range as the real markers), so a legal leading-empty-parameter SGR like `CSI ; 1 m` was being silently dropped; narrowed to `_csi.prefix! >= Ascii.lessThan`, confirmed by a regression test and the fork's full suite (115/115 passing). Independently re-confirmed end-to-end by re-running the exact captured banner bytes through the fixed parser (was: every row `underline=true`; now: every row `underline=false`). No existing upstream PR/issue covered this (checked before opening). Filed as [TerminalStudio/xterm.dart#230](https://github.com/TerminalStudio/xterm.dart/pull/230) — re-evaluate the override once (if) it's merged and released. **Updated during Task 4:** the pin moved from `c63f583` to `a766197` on the fork's `orthanc-integration` branch, which carries this SGR fix *plus* the `viewId` fix Task 4 uncovered ([#231](https://github.com/TerminalStudio/xterm.dart/pull/231), proposed upstream on its own branch so each PR stays independently reviewable). Retire the override only once both land in a release.

---

## Task 1: Project scaffold

**Files:**
- Create (via `flutter create`): `pubspec.yaml`, `lib/main.dart`, `macos/`, `windows/`, `test/widget_test.dart`, `analysis_options.yaml`, `.metadata`, `.gitignore`, `README.md`
- Modify: `pubspec.yaml` (add `flutter_pty` and `xterm` dependencies), `lib/main.dart` (replace the generated counter demo with an empty window), `test/widget_test.dart` (replace the counter tap/increment test with one that matches the new `OrthancApp`)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `class OrthancApp extends StatelessWidget` in `lib/main.dart`, run via `main()`. Later tasks replace its `home:` body but keep this shell.

- [ ] **Step 1: Scaffold the Flutter project**

Run from `~/orthanc` (already a git repo containing only `docs/`):

```bash
flutter create --platforms=macos,windows --project-name orthanc .
```

Expected: `pubspec.yaml`, `lib/main.dart`, `macos/`, `windows/`, `test/widget_test.dart` and the other standard scaffold files appear; `docs/` and `.git/` are untouched.

- [ ] **Step 2: Add dependencies**

Edit `pubspec.yaml`, adding under `dependencies:` (alongside the existing `flutter:` entry):

```yaml
  flutter_pty: ^0.4.2
  xterm: ^4.0.0
```

Run:

```bash
flutter pub get
```

Expected: resolves cleanly, `pubspec.lock` updated, no version conflicts.

- [ ] **Step 3: Replace the generated widget test with one that expects the empty window**

Replace the full contents of `test/widget_test.dart` (this fails against the still-in-place counter demo — that's the point):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/main.dart';

void main() {
  testWidgets('renders an empty window with no counter UI', (tester) async {
    await tester.pumpWidget(const OrthancApp());

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `flutter test`
Expected: FAIL — `findsNothing` fails because the generated counter demo's `FloatingActionButton` is still there.

- [ ] **Step 5: Replace the generated main.dart with an empty window**

Replace the full contents of `lib/main.dart`:

```dart
import 'package:flutter/material.dart';

void main() {
  runApp(const OrthancApp());
}

class OrthancApp extends StatelessWidget {
  const OrthancApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Orthanc',
      debugShowCheckedModeBanner: false,
      home: Scaffold(),
    );
  }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 7: Manual verification — empty window builds and runs**

Run:

```bash
flutter run -d macos
```

Expected: a window titled "Orthanc" opens with a blank body, no errors in the console. This matches the spec's own Step 1 verification ("empty window builds and runs on macOS"); the widget test above already covers the Scaffold's presence, this run confirms it actually launches as a real desktop window. Stop the run (`q` in the terminal) once confirmed.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/main.dart test/widget_test.dart macos windows analysis_options.yaml .metadata .gitignore README.md
git commit -m "Scaffold Orthanc Flutter project (macOS + Windows)"
```

---

## Task 2: Spawn a shell (not Claude yet)

**Files:**
- Create: `lib/shell_command.dart`, `test/shell_command_test.dart`, `lib/pty_terminal.dart`, `test/pty_terminal_test.dart`
- Modify: `lib/main.dart` (render `PtyTerminal` instead of the empty `Scaffold`)

**Interfaces:**
- Consumes: `OrthancApp` shell from Task 1.
- Produces:
  - `String shellCommand({required bool isWindows, required Map<String, String> environment})` in `lib/shell_command.dart` — pure function, no I/O, callable with fakes.
  - `class PtyTerminal extends StatefulWidget` in `lib/pty_terminal.dart`, constructor `PtyTerminal({Key? key, required String executable, List<String> arguments = const []})`. Task 3 reuses this widget unchanged, only swapping what's passed as `executable`.

- [ ] **Step 1: Write the failing test for shellCommand**

Create `test/shell_command_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/shell_command.dart';

void main() {
  test('returns cmd.exe on Windows', () {
    final expected = 'cmd.exe';
    final result = shellCommand(isWindows: true, environment: const {});
    expect(result, expected);
  });

  test('returns the SHELL environment variable on non-Windows when set', () {
    final expected = '/bin/zsh';
    final result = shellCommand(
      isWindows: false,
      environment: const {'SHELL': '/bin/zsh'},
    );
    expect(result, expected);
  });

  test('falls back to bash on non-Windows when SHELL is unset', () {
    final expected = 'bash';
    final result = shellCommand(isWindows: false, environment: const {});
    expect(result, expected);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/shell_command_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/shell_command.dart'` (the file doesn't exist yet).

- [ ] **Step 3: Implement shellCommand**

Create `lib/shell_command.dart`:

```dart
String shellCommand({
  required bool isWindows,
  required Map<String, String> environment,
}) {
  if (isWindows) return 'cmd.exe';
  return environment['SHELL'] ?? 'bash';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/shell_command_test.dart`
Expected: PASS — all 3 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/shell_command.dart test/shell_command_test.dart
git commit -m "Add platform-aware shellCommand()"
```

- [ ] **Step 6: Write the failing test for PtyTerminal's constructor**

Create `test/pty_terminal_test.dart`. This tests only the widget's public constructor contract — what `main.dart` relies on — never mounts the widget into a tree, and so never triggers `initState`/`endOfFrame` or the real `Pty.start` FFI call underneath it. (Confirmed by direct experiment: a mounted widget test in this Flutter version runs `endOfFrame.then(...)` continuations synchronously within the same `pumpWidget` call, so a `testWidgets`-style test here would actually spawn a real process. Plain construction, with no `pumpWidget`, avoids that entirely — the pty/terminal *behavior* genuinely can only be judged by running the app, which the manual verification step below does.)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pty_terminal.dart';

void main() {
  test('stores the executable and arguments it is given', () {
    final expectedExecutable = 'claude';
    final expectedArguments = ['--foo'];

    final widget = PtyTerminal(
      executable: expectedExecutable,
      arguments: expectedArguments,
    );

    expect(widget.executable, expectedExecutable);
    expect(widget.arguments, expectedArguments);
  });

  test('defaults arguments to an empty list', () {
    final expected = <String>[];

    final widget = PtyTerminal(executable: 'claude');

    expect(widget.arguments, expected);
  });
}
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `flutter test test/pty_terminal_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/pty_terminal.dart'` (the file doesn't exist yet).

- [ ] **Step 8: Implement the PtyTerminal widget**

Create `lib/pty_terminal.dart`. This wires `flutter_pty`'s `Pty` to `xterm.dart`'s `Terminal`/`TerminalView`, following the pattern documented in the `xterm` package's own example app (verified against xterm 4.0.0 / flutter_pty 0.4.2 source). The constructor satisfies Step 6's test; the rest of the class (the actual pty/terminal wiring) is what the manual verification in Step 12 checks — no automated test reaches it, for the reason given above.

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class PtyTerminal extends StatefulWidget {
  const PtyTerminal({
    super.key,
    required this.executable,
    this.arguments = const [],
  });

  final String executable;
  final List<String> arguments;

  @override
  State<PtyTerminal> createState() => _PtyTerminalState();
}

class _PtyTerminalState extends State<PtyTerminal> {
  final terminal = Terminal(maxLines: 10000);
  final terminalController = TerminalController();
  late final Pty pty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (mounted) _startPty();
    });
  }

  void _startPty() {
    pty = Pty.start(
      widget.executable,
      arguments: widget.arguments,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
    );

    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen(terminal.write);

    pty.exitCode.then((code) {
      terminal.write('the process exited with exit code $code');
    });

    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (w, h, pw, ph) {
      pty.resize(h, w);
    };
  }

  @override
  void dispose() {
    pty.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      terminal,
      controller: terminalController,
      autofocus: true,
    );
  }
}
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `flutter test test/pty_terminal_test.dart`
Expected: PASS — both tests green. (This only exercises the constructor; it does not run `initState`, so it doesn't touch `Pty.start`.)

- [ ] **Step 10: Commit**

```bash
git add lib/pty_terminal.dart test/pty_terminal_test.dart
git commit -m "Add PtyTerminal widget wiring flutter_pty to xterm"
```

- [ ] **Step 11: Wire it into main.dart**

Replace `lib/main.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import 'pty_terminal.dart';
import 'shell_command.dart';

void main() {
  runApp(const OrthancApp());
}

class OrthancApp extends StatelessWidget {
  const OrthancApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orthanc',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: PtyTerminal(
            executable: shellCommand(
              isWindows: Platform.isWindows,
              environment: Platform.environment,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 12: Manual verification — plain shell behaves correctly**

Run:

```bash
flutter run -d macos
```

In the running window, check each of (matches the spec's Step 2 verification exactly):
- `ls` and `pwd` print correctly, prompt returns after each.
- Up/down arrow keys recall shell history.
- `clear` (or Cmd+K if the shell binds it) clears the screen without leaving stray characters.
- No garbled/misplaced escape sequences anywhere above.

This is PtyTerminal's real behavioral gate — no automated test reaches the pty/terminal wiring itself, only its constructor (Step 6-9). Stop the run once confirmed.

- [ ] **Step 13: Commit**

```bash
git add lib/main.dart
git commit -m "Wire flutter_pty + xterm to spawn a plain shell"
```

---

## Task 3: Spawn Claude Code

**Files:**
- Create: `lib/claude_command.dart`, `test/claude_command_test.dart`
- Modify: `lib/main.dart` (swap the spawned command from `shellCommand()` to `resolveClaudeCommand()`)

**Interfaces:**
- Consumes: `PtyTerminal` from Task 2, unchanged.
- Produces:
  - `List<String> knownClaudePaths({required String home, required bool isWindows})` in `lib/claude_command.dart`.
  - `String resolveClaudeCommand({required String home, required bool isWindows, required bool Function(String path) exists})` in `lib/claude_command.dart`.

- [ ] **Step 1: Write the failing tests**

Create `test/claude_command_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/claude_command.dart';

void main() {
  test('lists native-installer and Homebrew paths on macOS/Linux', () {
    final expected = [
      '/home/larry/.local/bin/claude',
      '/opt/homebrew/bin/claude',
      '/usr/local/bin/claude',
    ];
    final result = knownClaudePaths(home: '/home/larry', isWindows: false);
    expect(result, expected);
  });

  test('lists native-installer and npm paths on Windows', () {
    final expected = [
      r'C:\Users\larry\.local\bin\claude.exe',
      r'C:\Users\larry\AppData\Roaming\npm\claude.cmd',
    ];
    final result = knownClaudePaths(home: r'C:\Users\larry', isWindows: true);
    expect(result, expected);
  });

  test('resolves to the first existing known path', () {
    final expected = '/opt/homebrew/bin/claude';
    final result = resolveClaudeCommand(
      home: '/home/larry',
      isWindows: false,
      exists: (path) => path == '/opt/homebrew/bin/claude',
    );
    expect(result, expected);
  });

  test('falls back to the bare command when no known path exists', () {
    final expected = 'claude';
    final result = resolveClaudeCommand(
      home: '/home/larry',
      isWindows: false,
      exists: (path) => false,
    );
    expect(result, expected);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/claude_command_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/claude_command.dart'`.

- [ ] **Step 3: Implement claude_command.dart**

Create `lib/claude_command.dart`. The known paths reflect how Claude Code is actually installed: the native installer places it at `~/.local/bin/claude` (a symlink into `~/.local/share/claude/versions/<version>`), with Homebrew and generic npm-global locations as fallbacks. The app can't rely on plain `PATH` lookup because a GUI app launched from Finder/Explorer does not inherit an interactive shell's `PATH`.

```dart
List<String> knownClaudePaths({
  required String home,
  required bool isWindows,
}) {
  if (isWindows) {
    return [
      '$home\\.local\\bin\\claude.exe',
      '$home\\AppData\\Roaming\\npm\\claude.cmd',
    ];
  }
  return [
    '$home/.local/bin/claude',
    '/opt/homebrew/bin/claude',
    '/usr/local/bin/claude',
  ];
}

String resolveClaudeCommand({
  required String home,
  required bool isWindows,
  required bool Function(String path) exists,
}) {
  for (final path in knownClaudePaths(home: home, isWindows: isWindows)) {
    if (exists(path)) return path;
  }
  return 'claude';
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/claude_command_test.dart`
Expected: PASS — all 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/claude_command.dart test/claude_command_test.dart
git commit -m "Add resolveClaudeCommand() for per-platform claude lookup"
```

- [ ] **Step 6: Swap main.dart to spawn claude instead of a shell**

Replace `lib/main.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import 'claude_command.dart';
import 'pty_terminal.dart';

void main() {
  runApp(const OrthancApp());
}

class OrthancApp extends StatelessWidget {
  const OrthancApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orthanc',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: PtyTerminal(
            executable: resolveClaudeCommand(
              home: Platform.environment['HOME'] ??
                  Platform.environment['USERPROFILE'] ??
                  '',
              isWindows: Platform.isWindows,
              exists: (path) => File(path).existsSync(),
            ),
          ),
        ),
      ),
    );
  }
}
```

Note `shell_command.dart` is no longer imported here — it's still Task 2's file on disk (and still covered by its own test), just no longer wired into `main()`.

- [ ] **Step 7: Manual verification — Claude Code TUI renders and takes input**

Run:

```bash
flutter run -d macos
```

Check each of (matches the spec's Step 3 verification exactly):
- The Claude Code TUI renders (banner, prompt box) instead of a raw shell prompt.
- Typing at the prompt and submitting is accepted.
- Streaming output and screen redraws (e.g. the thinking spinner, tool-call blocks) look correct, not garbled or torn.

Stop the run once confirmed.

- [ ] **Step 8: Commit**

```bash
git add lib/main.dart
git commit -m "Spawn Claude Code instead of a plain shell"
```

---

## Task 4: Cross-platform pass (Windows)

**Run and passed 2026-07-20, on a Windows 11 machine.** Originally deferred (this plan was executed on darwin, which cannot run the Windows target); picked up later the same day when a Windows machine was available. Milestone 0's definition of done — parity on both platforms — is now met, and the Deferred-list gate is lifted.

**Outcome in one line:** ConPTY was never the problem. The pty layer, rendering, resizing, escape handling and the `$HOME` working directory all worked on the first Windows build; three defects elsewhere had to be fixed before the checklist passed.

**Files:** `lib/pty_environment.dart` + `test/pty_environment_test.dart` (new), `lib/pty_terminal.dart` (call site), `pubspec.yaml` (fork ref bump). The `xterm` fixes landed in the pinned fork, not here.

**Interfaces:**
- Consumes: the full app from Task 3, unmodified going in.
- Produces: Milestone 0's definition of done — parity confirmed on both platforms.

- [x] **Step 1: Build and run on Windows**

`fvm flutter run -d windows` on Windows 11 Pro, Flutter 3.38.7, Visual Studio Community 2022. Built first try in 28.5s; window opened; `flutter test` 9/9 green on Windows. No ConPTY, CMake or MSVC trouble at any point.

- [x] **Step 2: Manual verification — same checklist as Tasks 2 and 3, on Windows**

Shell stage: `dir`, arrow-key history recall and `cls` all behave; no garbled escapes; the prompt opens at `$HOME` as intended.

Claude stage: the Claude Code TUI renders, accepts prompts, and streams/redraws correctly — no tearing, and no spurious underline, which is the first time the SGR fix has been exercised against a heavy TUI on Windows.

Both stages passed only after the three fixes in Step 3.

- [x] **Step 3: Fix the defects found — none of them ConPTY**

**(a) Dead keyboard input — missing `viewId`.** Letters did nothing while Enter, arrows and Ctrl-combos worked. `xterm`'s `CustomTextEdit` builds its `TextInputConfiguration` without a `viewId`; Flutter's Windows embedder rejects `TextInput.setClient` outright (`Could not set client, view ID is null`) and the connection never attaches. Printable characters have no other route, since `CustomTextEdit` — unlike `CustomKeyboardListener` — has no hardware-key fallback for them, while keys that map to a `TerminalKey` still travel the `Focus.onKeyEvent` path. That asymmetry is what made the failure look selective. macOS tolerates the omission via its implicit view, which is why Task 3 passed there. Fixed in the fork with `View.of(context).viewId`, matching Flutter's own `EditableText`; carries a regression test that fails on `master` (`Expected: <0>, Actual: <null>`) and passes with the fix. Upstream: [#231](https://github.com/TerminalStudio/xterm.dart/pull/231).

**(b) `claude` silently doing nothing — missing `SystemRoot`.** `flutter_pty` does not inherit the parent environment; it builds the child's from scratch, copying only `LOGNAME`/`USER`/`DISPLAY`/`LC_TYPE`/`HOME`/`PATH`. That allowlist is POSIX-shaped, and on Windows it drops `SystemRoot`, without which a spawned executable loads no system DLLs and dies before printing anything. Confirmed outside the GUI by reproducing the exact child environment: `claude --version` produced no stdout *and no stderr* (so it was found and launched, not missing); adding `SystemRoot` alone gave `2.1.215 (Claude Code)`, exit 0. Fixed here in `lib/pty_environment.dart` — forward the whole environment on Windows, as a terminal emulator is expected to — with unit tests for both branches. `Pty.start(environment:)` is the package's own supported escape hatch, so no upstream change was needed.

**(c) Not a defect: colorless TUI.** Forwarding the environment also forwards `NO_COLOR`, which Claude Code sets for its subprocesses; the spawned `claude` honored it. Verified by relaunching with only that variable removed — color returned. Correct inheritance, recorded so the next reader does not chase it.

- [x] **Step 4: Commit**

Committed with the plan and README updated to match.

Once Step 2's checklist passes cleanly on both macOS and Windows, Milestone 0 is done: the pty risk is retired, and everything from here (multi-session, card-grid overview, session lifecycle, configurable commands) becomes ordinary Flutter UI work, per the spec's Deferred list.

---

## Self-Review

**Spec coverage:** Spec Steps 1–4 map 1:1 to Tasks 1–4. Spec's Definition of Done is Task 4's closing checklist. Spec's Deferred list is called out in Global Constraints and repeated at Task 4's end so a future session doesn't fold it in here.

**Placeholder scan:** no TBD/TODO; every step shows the actual code or command. Task 4 is verification-shaped rather than code-shaped because the spec itself frames Windows as risk-discovery, not a pre-known fix — that's stated explicitly rather than left as an implicit gap.

**Type consistency:** `shellCommand({required bool isWindows, required Map<String,String> environment})` — same signature at definition (Task 2 Step 3), test (Task 2 Step 1), and call site (Task 2 Step 11). `PtyTerminal({required String executable, List<String> arguments = const []})` — same across definition (Task 2 Step 8), its constructor test (Task 2 Step 6), and both call sites (Task 2 Step 11, Task 3 Step 6). `resolveClaudeCommand({required String home, required bool isWindows, required bool Function(String) exists})` — same across definition, test, and call site in Task 3.

**Test-coverage note (post pre-flight discussion):** Tasks 1 and 2 originally shipped the empty `Scaffold` and `PtyTerminal` with no automated test, reasoning that neither had logic a test could reach. Per the user's explicit call in pre-flight review, the style rule governs instead: Task 1 now carries a `testWidgets` check (safe — `OrthancApp` has no async scheduling), and Task 2 carries a plain `test()` against `PtyTerminal`'s constructor only (verified experimentally that mounting it via `pumpWidget` would actually invoke the real `Pty.start` FFI call in this Flutter version, since `endOfFrame` continuations run synchronously within a single `pump`). The pty/terminal wiring's actual behavior remains covered only by the manual verification steps — that part of the original reasoning still holds.

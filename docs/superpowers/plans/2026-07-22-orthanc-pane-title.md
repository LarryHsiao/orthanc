# Orthanc — Pane Title: Name, Activity, and Idle pwd Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pane's title bar (`PaneBar`) shows the Claude Code session's name and its current activity together instead of one overwriting the other, and reflects the shell's pwd once Claude exits back to an idle prompt instead of showing a stale title.

**Architecture:** `Session` splits its single `title` notifier into `name` (OSC 1 / icon) and `activity` (OSC 2 / window title); a new pure `paneTitle()` combines them for display; a new `shell_prompt_hook.dart` builds the platform-specific extras (`Pty.start` arguments/environment) that make each pane's shell announce its own pwd via OSC 2 on every prompt redraw.

**Tech Stack:** Flutter desktop (macOS + Windows), `flutter_pty` 0.4.2, pinned `xterm.dart` fork, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md` — read it first; this plan implements it task by task.

## Global Constraints

- Dart SDK `^3.10.7` (`pubspec.yaml`).
- Desktop targets are macOS and Windows only — no Linux.
- `xterm` stays pinned to the fork at `a766197d21a516d7e949bb095acbea2b0b707e09` (`pubspec.yaml` `dependency_overrides`) — do not bump it as part of this work.
- The native OS window title bar is never touched — this feature is entirely inside `PaneBar`.
- No manual rename UI for either `name` or `activity` — both are program-set only.
- Any shell prompt hook must emit OSC **2** only, never OSC 0 — OSC 0 also sets OSC 1 (icon/name), which would silently overwrite the session name every time the shell redraws its prompt.
- Shell prompt hook scope is exactly bash/zsh (macOS) and `cmd.exe` (Windows) — matching what `shellCommand()` (`lib/shell_command.dart`) spawns today. Any other shell is left completely alone, not partially or incorrectly hooked.
- A shell prompt hook must never mutate the user's actual `.bashrc`/`.zshrc` on disk — it sources the user's real rc file from a separate temp file/dir it controls.

---

### Task 1: Verify how Claude Code uses OSC 1 vs OSC 2

**Files:** none — this is a manual investigation task. Its finding determines whether Task 2's channel mapping needs adjusting before being implemented.

**Interfaces:**
- Consumes: nothing.
- Produces: a recorded finding (appended to the spec's "Open question" section) that Task 2 reads before writing `Session`'s OSC wiring.

- [ ] **Step 1: Capture raw bytes from a real Claude Code session**

Run, from a normal terminal (not inside Orthanc, so the raw bytes are easy to inspect afterward):

```bash
script -q /tmp/orthanc-osc-capture.txt claude
```

This starts an interactive `claude` session with everything it outputs — including escape sequences — logged to `/tmp/orthanc-osc-capture.txt`.

- [ ] **Step 2: Reproduce both moments from the spec's examples**

Inside that session:
1. Give it a short task (e.g. ask it to check something) and let it work — this is the "activity" moment.
2. If Claude Code has a way to rename or retitle the current session (check `/help` inside the session for a relevant slash command), use it — this is the "rename" moment.
3. Exit the session (`exit` or Ctrl-D) to stop the `script` capture.

- [ ] **Step 3: Inspect the capture for OSC sequences**

```bash
od -c /tmp/orthanc-osc-capture.txt | grep -B1 -A1 '033   \]'
```

Each hit shows a chunk of the file around an escape (`033` = octal ESC) followed by `]`. An OSC sequence has the shape ESC `]` *Ps* `;` *text* (ESC `\` or BEL) — *Ps* is the parameter that matters: `0` (both channels), `1` (icon/name only), or `2` (title/activity only). Note, for both the activity moment and the rename moment, which *Ps* value appeared and what text followed it.

- [ ] **Step 4: Record the finding in the spec**

Open `docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md` and append under "Open question, resolved by a verification step, not a guess":

```markdown
**Verified 2026-07-22:** [one of the three outcomes below], based on capturing
`claude`'s raw output via `script` during a real session.
```

Followed by whichever of these matches what was observed:

- If activity used `Ps=2` and the rename used `Ps=1`: `"Confirmed — OSC 2 carries activity, OSC 1 carries the session name, exactly as designed. Task 2 proceeds with its default wiring unchanged."`
- If the mapping was reversed (activity on `Ps=1`, name on `Ps=2`): `"Reversed from the spec's assumption — OSC 1 carries activity, OSC 2 carries the session name. Task 2's onTitleChange/onIconChange assignments must be swapped from what's written below before committing."`
- If both moments used the same `Ps` (most likely `Ps=0`, or both `Ps=2`) with no separation: `"No separation — Claude Code does not split name from activity across OSC channels. Task 2 still adds the two fields for forward-compatibility, but name will never populate from Claude Code today; PaneBar's activity-only fallback (paneTitle() with an empty name) is what actually displays. This matches the spec's documented no-regression fallback, not a defect."`

- [ ] **Step 5: Commit the recorded finding**

```bash
git add docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md
git commit -m "Record OSC channel verification finding for pane title spec"
```

---

### Task 2: Split `Session.title` into `name` and `activity`

**Files:**
- Modify: `lib/session.dart:30-32` (field declarations), `lib/session.dart:91-93` (wiring), `lib/session.dart:105-111` (`dispose()`)
- Test: `test/session_test.dart`

**Interfaces:**
- Consumes: `Terminal.onTitleChange` and `Terminal.onIconChange` (both `void Function(String)?`, already present on the pinned `xterm.dart` fork's `Terminal` class).
- Produces: `Session.activity` and `Session.name`, both `ValueNotifier<String>`, for `PaneBar` (Task 3) to read. `Session.title` no longer exists.

If Task 1's finding says the mapping is reversed, swap which callback assigns to which notifier before committing this task. The code below assumes the default (unreversed) mapping.

- [ ] **Step 1: Write the failing tests**

Replace `test/session_test.dart` in full:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/session.dart';

void main() {
  test('stores the id and executable it is given', () {
    const expectedId = 'a';
    const expectedExecutable = 'cmd.exe';

    final session = Session(id: expectedId, executable: expectedExecutable);

    expect(session.id, expectedId);
    expect(session.executable, expectedExecutable);
  });

  test('starts with its activity set to its executable', () {
    const expectedActivity = 'cmd.exe';

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.activity.value, expectedActivity);
  });

  test('starts with no name', () {
    const expectedName = '';

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.name.value, expectedName);
  });

  test('dispose() on a never-started session does not throw', () {
    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.dispose, returnsNormally);
  });

  test('dispose() is safe to call twice', () {
    final session = Session(id: 'a', executable: 'cmd.exe');
    session.dispose();

    expect(session.dispose, returnsNormally);
  });
}
```

- [ ] **Step 2: Run the tests to verify the expected failures**

Run: `flutter test test/session_test.dart`
Expected: FAIL — `session.activity` and `session.name` don't exist yet (`title` does instead).

- [ ] **Step 3: Update `Session`**

In `lib/session.dart`, replace the single `title` field (lines 30-32):

```dart
  /// The title the running program sets for itself, via OSC 0/2 — the same one
  /// tmux and iTerm show. Claude Code writes its current task there.
  late final ValueNotifier<String> title = ValueNotifier(executable);
```

with two fields:

```dart
  /// What the running program is doing right now, via OSC 2 ("window
  /// title") — Claude Code's current task while it runs, or the shell's own
  /// prompt hook announcing its pwd once idle (see shell_prompt_hook.dart).
  late final ValueNotifier<String> activity = ValueNotifier(executable);

  /// The session's own name, via OSC 1 ("icon name") — set only when the
  /// running program renames itself; empty until then.
  late final ValueNotifier<String> name = ValueNotifier('');
```

Replace the `onTitleChange` wiring in `_wire()` (lines 91-93):

```dart
    terminal.onTitleChange = (value) {
      if (value.isNotEmpty) title.value = value;
    };
```

with:

```dart
    terminal.onTitleChange = (value) {
      if (value.isNotEmpty) activity.value = value;
    };

    terminal.onIconChange = (value) {
      if (value.isNotEmpty) name.value = value;
    };
```

Replace `title.dispose();` in `dispose()` (around line 110) with:

```dart
    activity.dispose();
    name.dispose();
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/session_test.dart`
Expected: PASS, all 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/session.dart test/session_test.dart
git commit -m "Split Session.title into name (OSC 1) and activity (OSC 2)"
```

---

### Task 3: Combine name and activity in the pane bar

**Files:**
- Create: `lib/pane_title.dart`
- Test: `test/pane_title_test.dart`
- Modify: `lib/pane_bar.dart:30-43`

**Interfaces:**
- Consumes: `Session.name` and `Session.activity` (`ValueNotifier<String>`, from Task 2).
- Produces: `String paneTitle({required String name, required String activity})`, used only by `PaneBar`.

- [ ] **Step 1: Write the failing test**

Create `test/pane_title_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pane_title.dart';

void main() {
  test('shows activity alone when no name is set', () {
    const expected = 'check status';

    final result = paneTitle(name: '', activity: 'check status');

    expect(result, expected);
  });

  test('combines name and activity when both are set', () {
    const expected = 'A — check status';

    final result = paneTitle(name: 'A', activity: 'check status');

    expect(result, expected);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/pane_title_test.dart`
Expected: FAIL — `package:orthanc/pane_title.dart` does not exist.

- [ ] **Step 3: Write `paneTitle()`**

Create `lib/pane_title.dart`:

```dart
/// Combines a session's name and current activity into one line for
/// [PaneBar] — both are shown together rather than one overwriting the
/// other, since a running program can set either independently. See
/// docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md.
String paneTitle({required String name, required String activity}) {
  if (name.isEmpty) return activity;
  return '$name — $activity';
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/pane_title_test.dart`
Expected: PASS, both tests.

- [ ] **Step 5: Wire `PaneBar` to both notifiers**

In `lib/pane_bar.dart`, add the import:

```dart
import 'pane_title.dart';
```

Replace `_title()` (lines 30-43):

```dart
  Widget _title(ColorScheme scheme) {
    return ValueListenableBuilder(
      valueListenable: session.title,
      builder: (context, title, child) => Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: focused ? FontWeight.w700 : FontWeight.w400,
          color: scheme.onSurface,
        ),
      ),
    );
  }
```

with:

```dart
  Widget _title(ColorScheme scheme) {
    return ValueListenableBuilder(
      valueListenable: session.name,
      builder: (context, name, child) => ValueListenableBuilder(
        valueListenable: session.activity,
        builder: (context, activity, child) => Text(
          paneTitle(name: name, activity: activity),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: focused ? FontWeight.w700 : FontWeight.w400,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 6: Run the full test suite to confirm nothing else broke**

Run: `flutter test`
Expected: PASS, all tests (no widget test exists for `PaneBar` itself — consistent with Milestone 1's own testing table, which leaves `PaneView`/`SplitView` to the by-eye pass in Task 6).

- [ ] **Step 7: Commit**

```bash
git add lib/pane_title.dart test/pane_title_test.dart lib/pane_bar.dart
git commit -m "Show session name and activity together in the pane bar"
```

---

### Task 4: Build the shell prompt hook

**Files:**
- Create: `lib/shell_prompt_hook.dart`
- Test: `test/shell_prompt_hook_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ShellLaunch shellPromptHook({required bool isWindows, required String executable, required Map<String, String> environment})`, a class `ShellLaunch` with `List<String> arguments` and `Map<String, String> environment` fields (plus `ShellLaunch.none`), for Task 5's `Session._spawn()` to consume.

- [ ] **Step 1: Write the failing tests**

Create `test/shell_prompt_hook_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/shell_prompt_hook.dart';

void main() {
  group('shellKind', () {
    test('recognizes bash', () {
      const expected = ShellKind.bash;

      final result = shellKind('/bin/bash');

      expect(result, expected);
    });

    test('recognizes zsh', () {
      const expected = ShellKind.zsh;

      final result = shellKind('/bin/zsh');

      expect(result, expected);
    });

    test('returns null for a shell it does not know how to hook', () {
      const expected = null;

      final result = shellKind('/usr/bin/fish');

      expect(result, expected);
    });
  });

  group('bashPromptHookScript', () {
    test('sources the user rc file when one is given', () {
      final expected =
          '[ -f "/home/larry/.bashrc" ] && source "/home/larry/.bashrc"';

      final result = bashPromptHookScript(userBashrc: '/home/larry/.bashrc');

      expect(result.contains(expected), isTrue);
    });

    test('omits the source line when there is no user rc file', () {
      final result = bashPromptHookScript(userBashrc: null);

      expect(result.contains('source'), isFalse);
    });

    test('sets an OSC 2 title, never OSC 0, in the printf line', () {
      final result = bashPromptHookScript(userBashrc: null);

      expect(result.contains(']2;%s'), isTrue);
      expect(result.contains(']0;'), isFalse);
    });

    test('preserves any PROMPT_COMMAND the sourced rc file already set', () {
      final expected = r'${PROMPT_COMMAND:+; $PROMPT_COMMAND}';

      final result = bashPromptHookScript(userBashrc: null);

      expect(result.contains(expected), isTrue);
    });
  });

  group('zshPromptHookScript', () {
    test('sources the user rc file when one is given', () {
      final expected =
          '[ -f "/home/larry/.zshrc" ] && source "/home/larry/.zshrc"';

      final result = zshPromptHookScript(userZshrc: '/home/larry/.zshrc');

      expect(result.contains(expected), isTrue);
    });

    test('omits the source line when there is no user rc file', () {
      final result = zshPromptHookScript(userZshrc: null);

      expect(result.contains('source'), isFalse);
    });

    test('appends to precmd_functions rather than overwriting precmd', () {
      final expected = 'precmd_functions+=(__orthanc_title_hook)';

      final result = zshPromptHookScript(userZshrc: null);

      expect(result.contains(expected), isTrue);
    });
  });

  group('cmdPromptHookArguments', () {
    test('runs cmd.exe with /K so it stays interactive', () {
      const expected = '/K';

      final result = cmdPromptHookArguments();

      expect(result.first, expected);
    });

    test('sets an OSC 2 title, never OSC 0, via the PROMPT special codes', () {
      final result = cmdPromptHookArguments();

      expect(result.last.contains(r']2;'), isTrue);
      expect(result.last.contains(r']0;'), isFalse);
    });
  });

  group('shellPromptHook', () {
    test('uses the cmd.exe hook on Windows regardless of executable', () {
      final expected = cmdPromptHookArguments();

      final result = shellPromptHook(
        isWindows: true,
        executable: 'cmd.exe',
        environment: const {},
      );

      expect(result.arguments, expected);
    });

    test('returns no launch extras for a shell it does not know how to hook',
        () {
      const expected = ShellLaunch.none;

      final result = shellPromptHook(
        isWindows: false,
        executable: '/usr/bin/fish',
        environment: const {},
      );

      expect(result.arguments, expected.arguments);
      expect(result.environment, expected.environment);
    });

    test('writes a bash rcfile and points --rcfile at it', () {
      final result = shellPromptHook(
        isWindows: false,
        executable: '/bin/bash',
        environment: const {'HOME': '/home/larry'},
      );

      expect(result.arguments.first, '--rcfile');
      final rcFile = File(result.arguments.last);
      expect(rcFile.existsSync(), isTrue);
      expect(
        rcFile.readAsStringSync(),
        bashPromptHookScript(userBashrc: '/home/larry/.bashrc'),
      );
    });

    test('writes a zsh .zshrc and points ZDOTDIR at its directory', () {
      final result = shellPromptHook(
        isWindows: false,
        executable: '/bin/zsh',
        environment: const {'HOME': '/home/larry'},
      );

      expect(result.arguments, isEmpty);
      final zdotdir = result.environment['ZDOTDIR'];
      expect(zdotdir, isNotNull);
      final rcFile = File('$zdotdir/.zshrc');
      expect(rcFile.existsSync(), isTrue);
      expect(
        rcFile.readAsStringSync(),
        zshPromptHookScript(userZshrc: '/home/larry/.zshrc'),
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/shell_prompt_hook_test.dart`
Expected: FAIL — `package:orthanc/shell_prompt_hook.dart` does not exist.

- [ ] **Step 3: Write `lib/shell_prompt_hook.dart`**

```dart
import 'dart:io';

/// A shell this app knows how to add a title-on-prompt hook to.
enum ShellKind { bash, zsh }

/// Which [ShellKind] [executable] is, or null for a shell this app leaves
/// alone — its pane then just shows whatever title it last happened to set,
/// as before this feature existed.
ShellKind? shellKind(String executable) {
  final name = executable.split('/').last;
  if (name == 'bash') return ShellKind.bash;
  if (name == 'zsh') return ShellKind.zsh;
  return null;
}

/// The OSC 2 sequence, in shell syntax, that announces the shell's own
/// working directory as the pane's current activity. OSC 2 specifically —
/// never OSC 0 — so it never touches the session name a running program set
/// on OSC 1.
const _titleHookFunction = r'''
__orthanc_title_hook() {
  printf '\033]2;%s\033\\' "$PWD"
}
''';

/// The rc file bash should read instead of `~/.bashrc`: sources the user's
/// own rc file first (if [userBashrc] is given), then adds the title hook so
/// it fires on every prompt redraw, without discarding whatever the user's
/// own `PROMPT_COMMAND` already did.
String bashPromptHookScript({required String? userBashrc}) {
  final source = userBashrc == null
      ? ''
      : '[ -f "$userBashrc" ] && source "$userBashrc"\n';
  return '$source$_titleHookFunction'
      'PROMPT_COMMAND="__orthanc_title_hook\${PROMPT_COMMAND:+; \$PROMPT_COMMAND}"\n';
}

/// The `.zshrc` a temporary `ZDOTDIR` should hold: sources the user's own
/// `.zshrc` first (if [userZshrc] is given), then adds the title hook to
/// `precmd_functions` so it fires on every prompt redraw alongside whatever
/// hooks the user's own rc file already installed.
String zshPromptHookScript({required String? userZshrc}) {
  final source =
      userZshrc == null ? '' : '[ -f "$userZshrc" ] && source "$userZshrc"\n';
  return '$source$_titleHookFunction'
      'precmd_functions+=(__orthanc_title_hook)\n';
}

/// The `cmd.exe` arguments that make it announce its own path as the pane's
/// current activity on every prompt: `$P` (path) and `$G$S` (`> `, cmd's own
/// default prompt tail) are both re-evaluated by cmd.exe on every prompt
/// redraw, so — unlike bash/zsh — no rc-file injection is needed.
List<String> cmdPromptHookArguments() {
  return ['/K', r'prompt $E]2;$P$E\$P$G$S'];
}

/// What to hand `Pty.start`, on top of what [executable] already needs, so
/// the pane announces its own pwd once idle instead of showing a stale title
/// a finished program left behind.
class ShellLaunch {
  const ShellLaunch({required this.arguments, required this.environment});

  static const none = ShellLaunch(arguments: [], environment: {});

  final List<String> arguments;
  final Map<String, String> environment;
}

/// Builds [executable]'s [ShellLaunch], writing whatever temp rc file its
/// shell needs. Returns [ShellLaunch.none] for a shell this app doesn't know
/// how to hook — see [shellKind].
ShellLaunch shellPromptHook({
  required bool isWindows,
  required String executable,
  required Map<String, String> environment,
}) {
  if (isWindows) {
    return ShellLaunch(
      arguments: cmdPromptHookArguments(),
      environment: const {},
    );
  }
  switch (shellKind(executable)) {
    case ShellKind.bash:
      return _installBashHook(environment: environment);
    case ShellKind.zsh:
      return _installZshHook(environment: environment);
    case null:
      return ShellLaunch.none;
  }
}

ShellLaunch _installBashHook({required Map<String, String> environment}) {
  final home = environment['HOME'];
  final userBashrc = home == null ? null : '$home/.bashrc';
  final dir = Directory.systemTemp.createTempSync('orthanc-bash-');
  File(
    '${dir.path}/bashrc',
  ).writeAsStringSync(bashPromptHookScript(userBashrc: userBashrc));
  return ShellLaunch(
    arguments: ['--rcfile', '${dir.path}/bashrc'],
    environment: const {},
  );
}

ShellLaunch _installZshHook({required Map<String, String> environment}) {
  final originalZdotdir = environment['ZDOTDIR'] ?? environment['HOME'];
  final userZshrc =
      originalZdotdir == null ? null : '$originalZdotdir/.zshrc';
  final dir = Directory.systemTemp.createTempSync('orthanc-zsh-');
  File(
    '${dir.path}/.zshrc',
  ).writeAsStringSync(zshPromptHookScript(userZshrc: userZshrc));
  return ShellLaunch(arguments: const [], environment: {'ZDOTDIR': dir.path});
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/shell_prompt_hook_test.dart`
Expected: PASS, all tests.

- [ ] **Step 5: Commit**

```bash
git add lib/shell_prompt_hook.dart test/shell_prompt_hook_test.dart
git commit -m "Add shell prompt hook builder for pwd-on-idle title"
```

---

### Task 5: Wire the prompt hook into `Session`

**Files:**
- Modify: `lib/session.dart:1-9` (imports), `lib/session.dart:57-73` (`_spawn()`)

**Interfaces:**
- Consumes: `shellPromptHook()` and `ShellLaunch` from Task 4.
- Produces: nothing new — this task only changes what `Session._spawn()` hands to `Pty.start`.

No new automated test: `Session._spawn()` is already outside the unit-tested boundary (Milestone 1's own testing table: "`Session` — constructor only; the wiring needs the app"), since it starts a real process. Task 6 confirms this by hand.

- [ ] **Step 1: Add the import**

In `lib/session.dart`, add alongside the existing imports:

```dart
import 'shell_prompt_hook.dart';
```

- [ ] **Step 2: Update `_spawn()`**

Replace `_spawn()`:

```dart
  Pty _spawn() {
    // Without an explicit workingDirectory, Pty.start() defaults to wherever
    // this process's own cwd happens to be — unpredictable for a real
    // double-clicked .app, not just this dev session. Default to $HOME.
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return Pty.start(
      executable,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
      environment: ptyEnvironment(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
      ),
      workingDirectory: home,
    );
  }
```

with:

```dart
  Pty _spawn() {
    // Without an explicit workingDirectory, Pty.start() defaults to wherever
    // this process's own cwd happens to be — unpredictable for a real
    // double-clicked .app, not just this dev session. Default to $HOME.
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final hook = shellPromptHook(
      isWindows: Platform.isWindows,
      executable: executable,
      environment: Platform.environment,
    );
    final env = ptyEnvironment(
      isWindows: Platform.isWindows,
      environment: Platform.environment,
    );
    return Pty.start(
      executable,
      arguments: hook.arguments,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
      environment: {...?env, ...hook.environment},
      workingDirectory: home,
    );
  }
```

- [ ] **Step 3: Run the full test suite**

Run: `flutter test`
Expected: PASS, every test (this task adds no new tests; it must not break existing ones).

- [ ] **Step 4: Commit**

```bash
git add lib/session.dart
git commit -m "Wire the shell prompt hook into Session's spawned pty"
```

---

### Task 6: Confirm by hand

**Files:** none — this task runs the app and watches it, per this project's established pattern (M0 and M1 both closed the same way; pty/terminal wiring cannot be proven by `flutter test`, only watched).

**Interfaces:**
- Consumes: the whole feature, as built by Tasks 1-5.
- Produces: a pass/fail judgment recorded in this plan's checklist and, if anything is found broken, a fix before considering the feature done.

- [ ] **Step 1: Run on macOS**

```bash
flutter run -d macos
```

- [ ] **Step 2: Confirm activity shows**

In a pane, run `claude` and give it a short task. Confirm the pane bar's text updates to reflect what it's doing (not just its initial shell/executable label).

- [ ] **Step 3: Confirm name and activity coexist**

If Task 1 found a working rename mechanism, use it, then give Claude another short task. Confirm the pane bar shows both — `"$name — $activity"` — and that the activity keeps updating without the name disappearing. If Task 1 found no separation exists, confirm instead that the pane bar still shows activity alone with no visual glitch (the documented fallback).

- [ ] **Step 4: Confirm idle pwd**

Exit the `claude` process (`exit` or Ctrl-D) back to the shell prompt. Confirm the pane bar updates to the shell's current directory within one prompt redraw, replacing whatever Claude last showed. `cd` to a different directory and confirm the pane bar follows on the next prompt.

- [ ] **Step 5: Confirm the OS window title is untouched**

Confirm the actual OS window title bar (not `PaneBar`) has not changed throughout Steps 2-4 — it should read exactly what it did before this feature existed.

- [ ] **Step 6: Note the Windows pass as outstanding**

This plan's Task 6 can only be executed on macOS from this environment. Windows (`cmd.exe`'s prompt hook, in particular) has not been run by hand as part of this plan and must be confirmed separately, matching M0's and M1's own precedent of a required, separate Windows walk before either was called done.

- [ ] **Step 7: Commit anything Step 2-5 required fixing**

If the by-eye pass surfaced a fix, commit it with a message describing what was observed and what changed — do not fold silent fixes into this checklist item without recording what broke.

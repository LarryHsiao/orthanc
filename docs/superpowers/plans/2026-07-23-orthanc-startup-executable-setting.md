# Orthanc Startup Executable Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A first, extensible preferences mechanism for Orthanc, whose first setting lets the user override the executable path each new pane spawns — reachable via a native "Settings…" entry on both platforms — instead of always spawning the platform-detected shell.

**Architecture:** A pure `Settings` model (one nullable field today) is (de)serialized to/from JSON by pure functions, persisted to a `settings.json` file under the platform's application-support directory by thin, explicitly-parameterized I/O functions. The loaded `Settings` lives app-wide in one `ValueNotifier<Settings>`, created once in `main()` before `runApp()`. `Sessions.spawn()` reads its current value at spawn time and threads it into `shellCommand()`, which returns the configured path when set and falls back to today's detection otherwise. A single `showSettingsDialog()` widget is reachable from two platform-native doors: macOS's app menu bar (`PlatformMenuBar`, pure Dart) and Windows's title-bar system menu (a small Win32 addition in `windows/runner`, wired to Dart over a `MethodChannel`).

**Tech Stack:** Flutter desktop (macOS + Windows), `path_provider` (new dependency, application-support directory), `path` (new dependency, platform-agnostic path joining), `flutter_test`.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-23-orthanc-startup-executable-setting-design.md`. Every decision there is binding; this plan implements it and adds nothing.
- Platforms: macOS and Windows only, matching the rest of the project.
- The setting is global only — no per-pane executable overrides, no per-pane plumbing. Milestone 1 explicitly deferred per-pane commands; do not reopen that.
- Plain text field only — no file-picker dialog.
- Exactly one setting (`executablePath`) is implemented in this pass. Do not add fields, sections, or hooks for settings not yet named.
- `lib/claude_command.dart`'s `resolveClaudeCommand()`/`knownClaudePaths()` are pre-existing dead code from Milestone 0. Do not touch, revive, or route through them.
- An empty/blank field means "use the default" and is always valid — it is never checked against `exists()`.
- Effect timing: a saved change applies to panes opened *after* the save; already-running panes keep the executable they were spawned with.
- Reject an invalid path at save time — never persist a path that fails the existence check.

## File Structure

| File | Responsibility |
|---|---|
| `lib/settings.dart` | `Settings` model, `normalizeExecutablePath()`, JSON (de)serialization. Pure, no I/O. |
| `lib/settings_store.dart` | `settingsFile()`, `readSettings()`, `writeSettings()` — thin, explicitly-parameterized file I/O. |
| `lib/settings_validation.dart` | `executableExists()` — pure, injectable existence check. |
| `lib/shell_command.dart` | Modified: `shellCommand()` gains an optional `configured` param. |
| `lib/sessions.dart` | Modified: `Sessions` takes a `ValueNotifier<Settings>` and reads it at spawn time. |
| `lib/settings_dialog.dart` | `showSettingsDialog()` and its backing `_SettingsDialog` widget. |
| `lib/main.dart` | Modified: loads `Settings` before `runApp()`; `OrthancApp` hosts the macOS menu entry and the Windows method-channel listener. |
| `lib/workspace_view.dart` | Modified: `WorkspaceView` takes the `ValueNotifier<Settings>` and threads it to `Sessions`. |
| `windows/runner/flutter_window.h` / `.cpp` | Modified: appends "Settings…" to the title bar's native system menu; forwards it to Dart over a `MethodChannel`. |

---

## Task 1: Settings model

**Files:**
- Create: `lib/settings.dart`, `test/settings_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class Settings { const Settings({this.executablePath}); final String? executablePath; }`; `String? normalizeExecutablePath(String? path)`; `Map<String, dynamic> settingsToJson(Settings settings)`; `Settings settingsFromJson(Map<String, dynamic> json)`. Every later task imports these exact names from `settings.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/settings_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';

void main() {
  test('round-trips executablePath through json', () {
    const expected = r'C:\custom\shell.exe';
    final settings = Settings(executablePath: expected);

    final result = settingsFromJson(settingsToJson(settings));

    expect(result.executablePath, expected);
  });

  test('a missing executablePath field decodes to null', () {
    const expected = null;

    final result = settingsFromJson(const {});

    expect(result.executablePath, expected);
  });

  test('a blank executablePath in json decodes to null', () {
    const expected = null;

    final result = settingsFromJson(const {'executablePath': '   '});

    expect(result.executablePath, expected);
  });

  test('normalizeExecutablePath trims a real path', () {
    const expected = r'C:\custom\shell.exe';

    final result = normalizeExecutablePath('  C:\\custom\\shell.exe  ');

    expect(result, expected);
  });

  test('normalizeExecutablePath treats a blank string as null', () {
    const expected = null;

    final result = normalizeExecutablePath('   ');

    expect(result, expected);
  });

  test('normalizeExecutablePath passes null through', () {
    const expected = null;

    final result = normalizeExecutablePath(null);

    expect(result, expected);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/settings_test.dart`
Expected: FAIL — `package:orthanc/settings.dart` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/settings.dart`:

```dart
/// The user's persisted preferences — currently just [executablePath].
class Settings {
  const Settings({this.executablePath});

  final String? executablePath;
}

/// A blank path means "use the default" — normalized to null wherever a
/// path is read from disk or from user input.
String? normalizeExecutablePath(String? path) {
  final trimmed = path?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

Map<String, dynamic> settingsToJson(Settings settings) {
  return {'executablePath': settings.executablePath};
}

Settings settingsFromJson(Map<String, dynamic> json) {
  return Settings(
    executablePath: normalizeExecutablePath(json['executablePath'] as String?),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/settings_test.dart`
Expected: PASS — 6 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/settings.dart test/settings_test.dart
git commit -m "feat: add Settings model with json (de)serialization"
```

---

## Task 2: Settings persistence

**Files:**
- Create: `lib/settings_store.dart`, `test/settings_store_test.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: `Settings`, `settingsToJson()`, `settingsFromJson()` from Task 1.
- Produces: `File settingsFile({required Directory supportDir})`; `Settings readSettings({required File file})`; `void writeSettings(Settings settings, {required File file})`. Task 7 calls all three; Task 6's dialog calls `writeSettings()`.

- [ ] **Step 1: Add dependencies**

In `pubspec.yaml`, under `dependencies:` (after `cupertino_icons`), add:

```yaml
  path_provider: ^2.1.4
  path: ^1.9.0
```

Run: `flutter pub get`
Expected: resolves cleanly, `pubspec.lock` updated.

- [ ] **Step 2: Write the failing test**

Create `test/settings_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/settings_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('orthanc_settings_store_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('reading a missing settings file returns the default settings', () {
    const expected = null;
    final file = settingsFile(supportDir: tempDir);

    final result = readSettings(file: file);

    expect(result.executablePath, expected);
  });

  test('writing then reading round-trips the executable path', () {
    const expected = r'C:\custom\shell.exe';
    final file = settingsFile(supportDir: tempDir);

    writeSettings(const Settings(executablePath: expected), file: file);
    final result = readSettings(file: file);

    expect(result.executablePath, expected);
  });

  test('reading a corrupt settings file returns the default settings', () {
    const expected = null;
    final file = settingsFile(supportDir: tempDir);
    file.createSync(recursive: true);
    file.writeAsStringSync('{not valid json');

    final result = readSettings(file: file);

    expect(result.executablePath, expected);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/settings_store_test.dart`
Expected: FAIL — `package:orthanc/settings_store.dart` not found.

- [ ] **Step 4: Write minimal implementation**

Create `lib/settings_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'settings.dart';

File settingsFile({required Directory supportDir}) {
  return File(p.join(supportDir.path, 'settings.json'));
}

Settings readSettings({required File file}) {
  if (!file.existsSync()) return const Settings();
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return const Settings();
    return settingsFromJson(decoded);
  } on FormatException {
    return const Settings();
  }
}

void writeSettings(Settings settings, {required File file}) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(settingsToJson(settings)));
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/settings_store_test.dart`
Expected: PASS — 3 tests green.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/settings_store.dart test/settings_store_test.dart
git commit -m "feat: persist Settings to a json file under application support"
```

---

## Task 3: Path validation

**Files:**
- Create: `lib/settings_validation.dart`, `test/settings_validation_test.dart`

**Interfaces:**
- Consumes: `normalizeExecutablePath()` from Task 1.
- Produces: `bool executableExists(String path, {required bool Function(String) exists})`. Task 6's dialog calls this on every keystroke to gate Save.

- [ ] **Step 1: Write the failing test**

Create `test/settings_validation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings_validation.dart';

void main() {
  test('a blank path is always valid', () {
    const expected = true;

    final result = executableExists('   ', exists: (_) => false);

    expect(result, expected);
  });

  test('a path is valid when it exists', () {
    const expected = true;

    final result = executableExists(
      r'C:\custom\shell.exe',
      exists: (path) => path == r'C:\custom\shell.exe',
    );

    expect(result, expected);
  });

  test('a path is invalid when it does not exist', () {
    const expected = false;

    final result = executableExists(
      r'C:\missing\shell.exe',
      exists: (_) => false,
    );

    expect(result, expected);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/settings_validation_test.dart`
Expected: FAIL — `package:orthanc/settings_validation.dart` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/settings_validation.dart`:

```dart
import 'settings.dart';

bool executableExists(String path, {required bool Function(String) exists}) {
  final normalized = normalizeExecutablePath(path);
  if (normalized == null) return true;
  return exists(normalized);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/settings_validation_test.dart`
Expected: PASS — 3 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/settings_validation.dart test/settings_validation_test.dart
git commit -m "feat: add executableExists path validation"
```

---

## Task 4: Configurable shellCommand()

**Files:**
- Modify: `lib/shell_command.dart`, `test/shell_command_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `shellCommand()` gains an optional `String? configured` param. Task 5's `Sessions.spawn()` passes `settings.value.executablePath` through it.

- [ ] **Step 1: Write the failing test**

Append to `test/shell_command_test.dart` (inside the existing `main()`, after the current three tests):

```dart
  test('returns the configured executable when set, regardless of platform', () {
    final expected = r'C:\custom\shell.exe';
    final result = shellCommand(
      isWindows: true,
      environment: const {},
      configured: expected,
    );
    expect(result, expected);
  });

  test('falls back to platform detection when configured is blank', () {
    final expected = 'cmd.exe';
    final result = shellCommand(
      isWindows: true,
      environment: const {},
      configured: '   ',
    );
    expect(result, expected);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shell_command_test.dart`
Expected: FAIL — no named parameter `configured`.

- [ ] **Step 3: Write minimal implementation**

Replace `lib/shell_command.dart` in full:

```dart
String shellCommand({
  required bool isWindows,
  required Map<String, String> environment,
  String? configured,
}) {
  final trimmed = configured?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  if (isWindows) return 'cmd.exe';
  return environment['SHELL'] ?? 'bash';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shell_command_test.dart`
Expected: PASS — 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/shell_command.dart test/shell_command_test.dart
git commit -m "feat: let shellCommand() accept a configured override"
```

---

## Task 5: Wire Sessions to Settings

**Files:**
- Modify: `lib/sessions.dart`, `test/sessions_test.dart`, `lib/workspace_view.dart`

**Interfaces:**
- Consumes: `Settings` from Task 1, `shellCommand(configured: …)` from Task 4.
- Produces: `Sessions({required ValueNotifier<Settings> settings})`. Task 7 replaces the temporary inline `ValueNotifier` this task adds to `workspace_view.dart` with one loaded from disk.

- [ ] **Step 1: Write the failing test**

Modify `test/sessions_test.dart` in full:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/sessions.dart';
import 'package:orthanc/settings.dart';

void main() {
  test('gives each session a distinct id', () {
    final sessions = Sessions(settings: ValueNotifier(const Settings()));

    final first = sessions.spawn();
    final second = sessions.spawn();

    expect(first.id, isNot(second.id));
  });

  test('finds a session by its id', () {
    final sessions = Sessions(settings: ValueNotifier(const Settings()));

    final session = sessions.spawn();

    expect(sessions[session.id], same(session));
  });

  test('forgets a removed session', () {
    const expected = null;
    final sessions = Sessions(settings: ValueNotifier(const Settings()));
    final session = sessions.spawn();

    sessions.remove(session.id);

    expect(sessions[session.id], expected);
  });

  test('spawns using the configured executable path when set', () {
    const expected = r'C:\custom\shell.exe';
    final sessions = Sessions(
      settings: ValueNotifier(const Settings(executablePath: expected)),
    );

    final session = sessions.spawn();

    expect(session.executable, expected);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sessions_test.dart`
Expected: FAIL — no named parameter `settings` on `Sessions()`.

- [ ] **Step 3: Write minimal implementation**

Replace `lib/sessions.dart` in full:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session.dart';
import 'settings.dart';
import 'shell_command.dart';

/// The living sessions, by id.
///
/// The layout tree owns the arrangement; this owns the things arranged. Neither
/// knows about the other, which is what keeps the tree testable.
class Sessions {
  Sessions({required this.settings});

  final ValueNotifier<Settings> settings;

  final _byId = <String, Session>{};
  var _next = 0;

  /// Starts a session running the configured executable, or the detected
  /// shell when none is configured — the same command for every pane.
  Session spawn() {
    final session = Session(
      id: '${_next++}',
      executable: shellCommand(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
        configured: settings.value.executablePath,
      ),
    );
    _byId[session.id] = session;
    return session;
  }

  Session? operator [](String id) => _byId[id];

  void remove(String id) {
    _byId.remove(id)?.dispose();
  }

  void disposeAll() {
    for (final session in _byId.values) {
      session.dispose();
    }
    _byId.clear();
  }
}
```

In `lib/workspace_view.dart`, add the import:

```dart
import 'settings.dart';
```

and change the `sessions` field on `_WorkspaceViewState` from:

```dart
  final sessions = Sessions();
```

to:

```dart
  final sessions = Sessions(settings: ValueNotifier(const Settings()));
```

(Task 7 replaces this inline default with the app-wide, disk-loaded notifier.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sessions_test.dart`
Expected: PASS — 4 tests green.

- [ ] **Step 5: Run the full suite to confirm nothing else broke**

Run: `flutter test`
Expected: PASS — all tests green.

- [ ] **Step 6: Commit**

```bash
git add lib/sessions.dart lib/workspace_view.dart test/sessions_test.dart
git commit -m "feat: spawn sessions using the configured executable"
```

---

## Task 6: Settings dialog

**Files:**
- Create: `lib/settings_dialog.dart`, `test/settings_dialog_test.dart`

**Interfaces:**
- Consumes: `Settings`, `normalizeExecutablePath()` (Task 1); `writeSettings()` (Task 2); `executableExists()` (Task 3).
- Produces: `Future<void> showSettingsDialog(BuildContext context, {required ValueNotifier<Settings> settings, required File file, required bool Function(String) exists, required String detectedDefault})`. Task 7 calls this from both platform entry points.

- [ ] **Step 1: Write the failing test**

Create `test/settings_dialog_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/settings_dialog.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('orthanc_settings_dialog_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<ValueNotifier<Settings>> pumpDialog(
    WidgetTester tester, {
    Settings initial = const Settings(),
    bool Function(String)? exists,
  }) async {
    final settings = ValueNotifier(initial);
    final file = File('${tempDir.path}/settings.json');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showSettingsDialog(
              context,
              settings: settings,
              file: file,
              exists: exists ?? (_) => true,
              detectedDefault: 'cmd.exe',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('field is prefilled with the current executablePath', (
    tester,
  ) async {
    const expected = r'C:\custom\shell.exe';

    await pumpDialog(tester, initial: const Settings(executablePath: expected));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, expected);
  });

  testWidgets('shows the detected default as placeholder text when unset', (
    tester,
  ) async {
    const expected = 'default: cmd.exe (detected)';

    await pumpDialog(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.hintText, expected);
  });

  testWidgets('typing a nonexistent path disables Save and shows an error', (
    tester,
  ) async {
    const expected =
        'No file exists at this path — the old value is kept.';
    await pumpDialog(tester, exists: (_) => false);

    await tester.enterText(find.byType(TextField), r'C:\missing\shell.exe');
    await tester.pump();

    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Save'),
    );
    expect(save.onPressed, isNull);
    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('Save persists a valid path and updates settings', (
    tester,
  ) async {
    const expected = r'C:\custom\shell.exe';
    final settings = await pumpDialog(tester);

    await tester.enterText(find.byType(TextField), expected);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(settings.value.executablePath, expected);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Reset clears the field and is disabled when already empty', (
    tester,
  ) async {
    const expected = '';
    await pumpDialog(tester, initial: const Settings(executablePath: 'x'));

    await tester.tap(find.widgetWithText(TextButton, 'Reset to default'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, expected);
    final reset = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Reset to default'),
    );
    expect(reset.onPressed, isNull);
  });

  testWidgets('Cancel closes without persisting', (tester) async {
    const expected = null;
    final settings = await pumpDialog(tester);

    await tester.enterText(find.byType(TextField), r'C:\custom\shell.exe');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(settings.value.executablePath, expected);
    expect(find.byType(TextField), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/settings_dialog_test.dart`
Expected: FAIL — `package:orthanc/settings_dialog.dart` not found.

- [ ] **Step 3: Write minimal implementation**

Create `lib/settings_dialog.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import 'settings.dart';
import 'settings_store.dart';
import 'settings_validation.dart';

/// Opens the Settings dialog, letting the user override the executable each
/// new pane spawns.
Future<void> showSettingsDialog(
  BuildContext context, {
  required ValueNotifier<Settings> settings,
  required File file,
  required bool Function(String) exists,
  required String detectedDefault,
}) {
  return showDialog(
    context: context,
    builder: (_) => _SettingsDialog(
      settings: settings,
      file: file,
      exists: exists,
      detectedDefault: detectedDefault,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settings,
    required this.file,
    required this.exists,
    required this.detectedDefault,
  });

  final ValueNotifier<Settings> settings;
  final File file;
  final bool Function(String) exists;
  final String detectedDefault;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _controller = TextEditingController(
    text: widget.settings.value.executablePath ?? '',
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => executableExists(_controller.text, exists: widget.exists);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Startup executable path'),
            const SizedBox(height: 4),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'default: ${widget.detectedDefault} (detected)',
                errorText: _valid
                    ? null
                    : 'No file exists at this path — the old value is kept.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _controller.text.isEmpty ? null : _reset,
          child: const Text('Reset to default'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _valid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _reset() => _controller.clear();

  void _save() {
    final updated = Settings(
      executablePath: normalizeExecutablePath(_controller.text),
    );
    widget.settings.value = updated;
    writeSettings(updated, file: widget.file);
    Navigator.pop(context);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/settings_dialog_test.dart`
Expected: PASS — 6 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/settings_dialog.dart test/settings_dialog_test.dart
git commit -m "feat: add the Settings dialog"
```

---

## Task 7: Load Settings at startup and wire the macOS entry point

**Files:**
- Modify: `lib/main.dart`, `lib/workspace_view.dart`

**Interfaces:**
- Consumes: `Settings`, `settingsFile()`, `readSettings()` (Tasks 1–2); `Sessions(settings: …)` (Task 5); `showSettingsDialog()` (Task 6); `shellCommand()` (Task 4).
- Produces: `WorkspaceView({required ValueNotifier<Settings> settings})`; `OrthancApp({required ValueNotifier<Settings> settings, required File settingsFile})`. Task 8 extends `_OrthancAppState` with the Windows method-channel listener.

- [ ] **Step 1: Replace `lib/main.dart` in full**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'settings.dart';
import 'settings_dialog.dart';
import 'settings_store.dart';
import 'shell_command.dart';
import 'workspace_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final file = settingsFile(supportDir: supportDir);
  final settings = ValueNotifier(readSettings(file: file));
  runApp(OrthancApp(settings: settings, settingsFile: file));
}

class OrthancApp extends StatefulWidget {
  const OrthancApp({
    super.key,
    required this.settings,
    required this.settingsFile,
  });

  final ValueNotifier<Settings> settings;
  final File settingsFile;

  @override
  State<OrthancApp> createState() => _OrthancAppState();
}

class _OrthancAppState extends State<OrthancApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  void _openSettings() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showSettingsDialog(
      context,
      settings: widget.settings,
      file: widget.settingsFile,
      exists: (path) => File(path).existsSync(),
      detectedDefault: shellCommand(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Orthanc',
          menus: [
            PlatformMenuItem(
              label: 'Settings…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: _openSettings,
            ),
          ],
        ),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Orthanc',
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(child: WorkspaceView(settings: widget.settings)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire `WorkspaceView` to the loaded settings**

In `lib/workspace_view.dart`, change the constructor from:

```dart
class WorkspaceView extends StatefulWidget {
  const WorkspaceView({super.key});
```

to:

```dart
class WorkspaceView extends StatefulWidget {
  const WorkspaceView({super.key, required this.settings});

  final ValueNotifier<Settings> settings;
```

and change the `sessions` field (added in Task 5) from:

```dart
  final sessions = Sessions(settings: ValueNotifier(const Settings()));
```

to:

```dart
  late final sessions = Sessions(settings: widget.settings);
```

- [ ] **Step 3: Run the full suite**

Run: `flutter test`
Expected: PASS — all tests green (no widget test constructs `WorkspaceView` directly, so this is a compile-level check).

- [ ] **Step 4: Verify static analysis is clean**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 5: Manual verification (macOS only — cannot be automated)**

Run: `flutter run -d macos`
Confirm by hand: the app's menu bar shows an "Orthanc" menu with a "Settings…" item (⌘,); selecting it opens the dialog from Task 6 over the running app.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart lib/workspace_view.dart
git commit -m "feat: load Settings at startup and add the macOS Settings menu"
```

---

## Task 8: Windows title-bar system-menu entry point

**Files:**
- Modify: `windows/runner/flutter_window.h`, `windows/runner/flutter_window.cpp`, `lib/main.dart`

**Interfaces:**
- Consumes: `_openSettings()` from Task 7 (extended, not replaced).
- Produces: nothing further downstream — this is the plan's final task.

- [ ] **Step 1: Replace `windows/runner/flutter_window.h` in full**

```cpp
#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Notifies Dart when the title bar's "Settings…" system-menu item fires.
  // macOS needs no native equivalent — its Settings entry lives in
  // PlatformMenuBar, in Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_menu_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
```

- [ ] **Step 2: Replace `windows/runner/flutter_window.cpp` in full**

```cpp
#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Must be a multiple of 16 — Windows reserves the low 4 bits of a
// WM_SYSCOMMAND wParam for its own built-in commands.
constexpr UINT_PTR kSettingsMenuId = 0x1000;

// The title bar's native right-click/system menu has no Flutter-side
// equivalent, so this appends "Settings…" to it directly via Win32.
void AppendSettingsMenuItem(HWND hwnd) {
  HMENU menu = GetSystemMenu(hwnd, FALSE);
  if (!menu) return;
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kSettingsMenuId, L"Settings…");
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  AppendSettingsMenuItem(GetHandle());

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  system_menu_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "orthanc/system_menu",
          &flutter::StandardMethodCodec::GetInstance());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SYSCOMMAND:
      if ((wparam & 0xFFF0) == kSettingsMenuId && system_menu_channel_) {
        system_menu_channel_->InvokeMethod("openSettings", nullptr);
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
```

- [ ] **Step 3: Add the Dart-side listener**

No new import is needed — Task 7's `lib/main.dart` already imports `package:flutter/services.dart`, which is where `MethodChannel` lives.

In `_OrthancAppState`, add a channel field and register its handler in `initState`:

```dart
class _OrthancAppState extends State<OrthancApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const _systemMenuChannel = MethodChannel('orthanc/system_menu');

  @override
  void initState() {
    super.initState();
    _systemMenuChannel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') _openSettings();
    });
  }

  void _openSettings() {
```

(The rest of `_openSettings()` and `build()` are unchanged from Task 7.)

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: PASS — all tests green.

- [ ] **Step 5: Verify the Windows build compiles**

Run: `flutter build windows`
Expected: builds successfully with no compiler errors in `flutter_window.cpp`/`.h`.

- [ ] **Step 6: Manual verification (Windows only — cannot be automated)**

Run: `flutter run -d windows`
Confirm by hand: right-clicking the title bar (or clicking the top-left icon) shows a "Settings…" item below the standard system-menu entries; selecting it opens the same dialog as the macOS path, over the running app.

- [ ] **Step 7: Commit**

```bash
git add windows/runner/flutter_window.h windows/runner/flutter_window.cpp lib/main.dart
git commit -m "feat: add the Windows title-bar Settings menu entry"
```

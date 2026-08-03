# Orthanc New Window (macOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "New Window" action (`Cmd+N`) on macOS that opens a second, fully independent Orthanc window — its own panes, its own pty sessions, its own lifecycle — while keeping settings changes synced live across every open window.

**Architecture:** Each additional window gets its own `FlutterEngine`, built directly by `AppDelegate` (macOS has no `FlutterEngineGroup`), signaled as "secondary" via `FlutterDartProject.dartEntrypointArguments`, which Dart reads synchronously as `main(List<String> args)`'s own argument list — no native↔Dart round trip needed for that signal. Settings stay a per-window `ValueNotifier<Settings>` as today, but each window now also watches `settings.json` on disk and reconciles on external change, so a save in one window reaches every other window with no custom IPC.

**Tech Stack:** Flutter desktop (macOS), no new pub dependencies — everything here is Dart `dart:io`/`dart:ui` plus native Swift/AppKit (`FlutterEngine`, `FlutterDartProject`, `NSWindow`).

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-08-03-orthanc-new-window-design.md`. Every decision there is binding; this plan implements it and adds nothing. Note its **Status** section: the originally-approved native mechanism was corrected before this plan was written (`FlutterEngineGroup`/`initialRoute` do not exist on macOS) — this plan implements the corrected mechanism only.
- macOS only. No Windows changes; Windows already has its own separate Settings entry point (`windows/runner/flutter_window.cpp`) and needs no equivalent for New Window.
- A new window always starts as a single default pane — never a copy of the calling window's layout.
- No new IPC/message-passing for settings sync — every window watches `settings.json` on disk independently.
- Update-check and the update-note banner run only in the primary window (the one open at launch); a window opened via "New Window" never calls `autoUpdater` or shows the banner.
- No "Window" menu, no window-arrangement UI — rely on macOS's own Cmd+`/Window menu as-is.
- `Settings` gains no `==`/`hashCode` override — `reconcileSettings()` compares its four fields directly.

## File Structure

| File | Responsibility |
|---|---|
| `lib/settings_watch.dart` | New. `reconcileSettings()` — pure decision on whether a freshly-read `Settings` differs from the current one. `watchSettingsFile()` — thin I/O: watches the settings file's directory, reloads and reconciles on a matching modify event. |
| `lib/main.dart` | Modified: `main(List<String> args)` computes `isPrimaryWindow` from `args`; calls `watchSettingsFile()` after the initial load; adds a "New Window" `PlatformMenuItem` (`Cmd+N`) that invokes `orthanc/system_menu.newWindow`; threads `isPrimaryWindow` into `AppRoot`. |
| `lib/app_root.dart` | Modified: `AppRoot` takes `required bool isPrimaryWindow`; `_showUpdateNoteIfAny()`/`_checkForUpdate()` only run when it's true. |
| `macos/Runner/AppDelegate.swift` | Modified: `createSecondaryWindow()` builds a direct `FlutterEngine` (with `dartEntrypointArguments: ["secondary"]`), wraps it in an `NSWindow`, and retains it in `secondaryWindows` until it closes. `configureSystemMenuChannel(on:)` wires the `newWindow` method on any given engine — shared by the primary engine and every secondary one. |
| `macos/Runner/MainFlutterWindow.swift` | Modified: after building its `FlutterViewController`, calls `AppDelegate`'s `configureSystemMenuChannel(on:)` on its own engine, so `Cmd+N` works from the first window too. |

---

## Task 1: Settings live sync

**Files:**
- Create: `lib/settings_watch.dart`, `test/settings_watch_test.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `Settings` (`lib/settings.dart`); `readSettings()` (`lib/settings_store.dart`).
- Produces: `Settings reconcileSettings({required Settings current, required Settings next})`; `void watchSettingsFile({required File file, required ValueNotifier<Settings> settings})`. Task 2 does not depend on either directly, but both must exist and be wired into `main.dart` before Task 2's manual walk (which checks settings sync across two real windows).

- [ ] **Step 1: Write the failing test**

Create `test/settings_watch_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/settings_watch.dart';

void main() {
  test('returns next when executablePath differs', () {
    const current = Settings(executablePath: 'a');
    const next = Settings(executablePath: 'b');

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(next));
  });

  test('returns next when colorScheme differs', () {
    const current = Settings(colorScheme: TerminalColorScheme.defaultScheme);
    const next = Settings(colorScheme: TerminalColorScheme.dracula);

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(next));
  });

  test('returns next when fontFamily differs', () {
    const current = Settings(fontFamily: TerminalFontFamily.defaultFamily);
    const next = Settings(fontFamily: TerminalFontFamily.menlo);

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(next));
  });

  test('returns next when fontSize differs', () {
    const current = Settings(fontSize: 12);
    const next = Settings(fontSize: 14);

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(next));
  });

  test('returns current unchanged when every field is identical', () {
    const current = Settings(
      executablePath: 'a',
      colorScheme: TerminalColorScheme.dracula,
      fontFamily: TerminalFontFamily.menlo,
      fontSize: 13,
    );
    const next = Settings(
      executablePath: 'a',
      colorScheme: TerminalColorScheme.dracula,
      fontFamily: TerminalFontFamily.menlo,
      fontSize: 13,
    );

    final result = reconcileSettings(current: current, next: next);

    expect(result, same(current));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/settings_watch_test.dart`
Expected: FAIL — `package:orthanc/settings_watch.dart` not found.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/settings_watch.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'settings.dart';
import 'settings_store.dart';

/// Returns [next] only when it differs from [current]; otherwise returns
/// [current] unchanged, so a caller can skip a needless [ValueNotifier]
/// update (and the rebuild it would trigger) on a no-op file event.
///
/// [Settings] carries no `==` override, so this compares its fields
/// directly rather than relying on identity equality.
Settings reconcileSettings({
  required Settings current,
  required Settings next,
}) {
  final changed = current.executablePath != next.executablePath ||
      current.colorScheme != next.colorScheme ||
      current.fontFamily != next.fontFamily ||
      current.fontSize != next.fontSize;
  return changed ? next : current;
}

/// Keeps [settings] in sync with [file] on disk: whenever another window's
/// save changes it, this window's panes see the new value without needing
/// to be reopened. A stream error (or a read landing mid atomic-rename) is
/// swallowed — the next filesystem event, or this window's own next
/// launch, resyncs state.
void watchSettingsFile({
  required File file,
  required ValueNotifier<Settings> settings,
}) {
  file.parent
      .watch(events: FileSystemEvent.modify)
      .where((event) => event.path == file.path)
      .listen((_) {
    settings.value = reconcileSettings(
      current: settings.value,
      next: readSettings(file: file),
    );
  }, onError: (_) {});
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/settings_watch_test.dart`
Expected: PASS — 5 tests green.

- [ ] **Step 5: Wire the watch into `main()`**

In `lib/main.dart`, add the import:

```dart
import 'settings_watch.dart';
```

and change `main()` from:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final file = settingsFile(supportDir: supportDir);
  final settings = ValueNotifier(readSettings(file: file));
  runApp(OrthancApp(settings: settings, settingsFile: file));
}
```

to:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final file = settingsFile(supportDir: supportDir);
  final settings = ValueNotifier(readSettings(file: file));
  watchSettingsFile(file: file, settings: settings);
  runApp(OrthancApp(settings: settings, settingsFile: file));
}
```

(Task 2 changes this signature again, to `main(List<String> args)` — this step only adds the watch call.)

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: PASS — all tests green (this is a compile-level check for `main.dart`; no test constructs `main()` directly).

- [ ] **Step 7: Verify static analysis is clean**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 8: Manual verification (macOS only — a filesystem watch cannot be exercised by `flutter_test`'s harness)**

Run: `flutter run -d macos`. While it's running, open `settings.json` under the app's application-support directory in a text editor (find the exact path by checking `getApplicationSupportDirectory()`'s target — typically `~/Library/Containers/<bundle id>/Data/Library/Application Support/orthanc/` or `~/Library/Application Support/orthanc/` depending on sandboxing) and hand-edit `fontSize` to a new value, then save the file.
Confirm by hand: the running app's terminal text visibly resizes within a second or two, with no restart.

- [ ] **Step 9: Commit**

```bash
git add lib/settings_watch.dart lib/main.dart test/settings_watch_test.dart
git commit -m "feat: sync Settings live across windows via a file watch"
```

---

## Task 2: macOS New Window

**Files:**
- Modify: `lib/main.dart`, `lib/app_root.dart`
- Modify: `macos/Runner/AppDelegate.swift`, `macos/Runner/MainFlutterWindow.swift`

**Interfaces:**
- Consumes: `watchSettingsFile()` (Task 1); existing `settingsFile()`/`readSettings()` (`lib/settings_store.dart`); existing `showSettingsDialog()` (`lib/settings_dialog.dart`); existing `orthanc/system_menu` `MethodChannel` (already used for `openSettings`, Windows-only today).
- Produces: `AppRoot({required ValueNotifier<Settings> settings, required bool isPrimaryWindow})`; a native `newWindow` method on `orthanc/system_menu`, and a native `AppDelegate.configureSystemMenuChannel(on: FlutterEngine)` entry point. This is the plan's final task — nothing downstream depends on these.

- [ ] **Step 1: Add `isPrimaryWindow` to `AppRoot`**

In `lib/app_root.dart`, change:

```dart
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.settings});

  final ValueNotifier<Settings> settings;
```

to:

```dart
class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.settings,
    required this.isPrimaryWindow,
  });

  final ValueNotifier<Settings> settings;
  final bool isPrimaryWindow;
```

and change `_AppRootState.initState()` from:

```dart
  @override
  void initState() {
    super.initState();
    _showUpdateNoteIfAny();
    _checkForUpdate();
  }
```

to:

```dart
  @override
  void initState() {
    super.initState();
    if (widget.isPrimaryWindow) {
      _showUpdateNoteIfAny();
      _checkForUpdate();
    }
  }
```

- [ ] **Step 2: Replace `lib/main.dart` in full**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_root.dart';
import 'settings.dart';
import 'settings_dialog.dart';
import 'settings_store.dart';
import 'settings_watch.dart';
import 'shell_command.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final file = settingsFile(supportDir: supportDir);
  final settings = ValueNotifier(readSettings(file: file));
  watchSettingsFile(file: file, settings: settings);
  runApp(OrthancApp(
    settings: settings,
    settingsFile: file,
    isPrimaryWindow: !args.contains('secondary'),
  ));
}

class OrthancApp extends StatefulWidget {
  const OrthancApp({
    super.key,
    required this.settings,
    required this.settingsFile,
    required this.isPrimaryWindow,
  });

  final ValueNotifier<Settings> settings;
  final File settingsFile;
  final bool isPrimaryWindow;

  @override
  State<OrthancApp> createState() => _OrthancAppState();
}

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

  Future<void> _openSettings() async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showSettingsDialog(
      context,
      settings: widget.settings,
      file: widget.settingsFile,
      exists: (path) => File(path).existsSync(),
      detectedDefault: shellCommand(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
      ),
      version: info.version,
    );
  }

  Future<void> _newWindow() => _systemMenuChannel.invokeMethod('newWindow');

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Orthanc',
          menus: [
            PlatformMenuItem(
              label: 'New Window',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: _newWindow,
            ),
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
          body: SafeArea(
            child: AppRoot(
              settings: widget.settings,
              isPrimaryWindow: widget.isPrimaryWindow,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Run the full suite**

Run: `flutter test`
Expected: PASS — all tests green (compile-level check; no test constructs `AppRoot` or `main()` directly).

- [ ] **Step 4: Verify static analysis is clean**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 5: Replace `macos/Runner/AppDelegate.swift` in full**

```swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Keeps each secondary NSWindow alive for as long as it's open — nothing
  // else retains it, and without this it would deallocate (and silently
  // close) the moment createSecondaryWindow() returns. Entries are removed
  // again on that window's own close, in createSecondaryWindow() below.
  private var secondaryWindows: [NSWindow] = []

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Wires the `orthanc/system_menu` channel's `newWindow` method on
  // `engine` to createSecondaryWindow() — called once for the primary
  // engine (from MainFlutterWindow) and once for every secondary engine
  // this itself creates, so Cmd+N works from any open window.
  func configureSystemMenuChannel(on engine: FlutterEngine) {
    let channel = FlutterMethodChannel(
      name: "orthanc/system_menu",
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "newWindow" {
        self?.createSecondaryWindow()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // macOS has no FlutterEngineGroup (that's iOS/Android-only) — each
  // additional window's engine is built directly: construct it, run it,
  // then wrap it in a FlutterViewController. dartEntrypointArguments tells
  // this window's Dart main() it's secondary, so it skips the update
  // check and opens with a single default pane rather than copying any
  // other window's layout.
  private func createSecondaryWindow() {
    let project = FlutterDartProject()
    project.dartEntrypointArguments = ["secondary"]
    let engine = FlutterEngine(name: "orthanc-secondary", project: project)
    // Fails silently by design, matching this app's existing precedent for
    // rare, low-stakes failures (AppRoot's update-check) — the user can
    // just press Cmd+N again rather than seeing an error dialog.
    guard engine.run(withEntrypoint: nil) else { return }

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    RegisterGeneratedPlugins(registry: controller)
    configureSystemMenuChannel(on: engine)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = controller
    window.center()
    window.makeKeyAndOrderFront(nil)

    secondaryWindows.append(window)
    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      self?.secondaryWindows.removeAll { $0 === window }
    }
  }
}
```

- [ ] **Step 6: Replace `macos/Runner/MainFlutterWindow.swift` in full**

```swift
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    (NSApp.delegate as? AppDelegate)?.configureSystemMenuChannel(
      on: flutterViewController.engine
    )

    super.awakeFromNib()
  }
}
```

- [ ] **Step 7: Run the full suite again**

Run: `flutter test`
Expected: PASS — all tests green (native changes don't affect `flutter test`, but this confirms Steps 5–6 didn't require any further Dart-side change).

- [ ] **Step 8: Verify the macOS build compiles**

Run: `flutter build macos`
Expected: builds successfully with no Swift compiler errors in `AppDelegate.swift`/`MainFlutterWindow.swift`. If the compiler flags `flutterViewController.engine` or any `FlutterEngine`/`FlutterDartProject` API used above, open the actual installed header (via Xcode's "Jump to Definition" on `FlutterViewController`/`FlutterEngine`/`FlutterDartProject`) and adjust to match — the exact declared optionality of `engine` was not independently confirmed against the local SDK the way `FlutterEngineGroup`'s absence was.

- [ ] **Step 9: Manual verification (macOS only — multi-window/multi-engine behavior cannot be exercised by `flutter_test`'s harness)**

Run: `flutter run -d macos`. Confirm by hand, in order:

1. The Orthanc menu shows a "New Window" item above "Settings…", bound to `Cmd+N`.
2. Pressing `Cmd+N` opens a second window with its own single default pane (not a copy of the first window's layout, if the first window had been split).
3. Typing in each window's pane runs an independent shell — output in one never appears in the other.
4. From the *second* window, press `Cmd+N` again — confirm a third window opens (proves the channel handler works from a secondary window too, not only the primary).
5. Open Settings from any window, change the color scheme or font, Save — confirm every other open window's panes update live within a second or two, no reopen needed.
6. Close one window — confirm the others are unaffected and keep running.
7. Close every window — confirm the app quits (the Dock icon and process both disappear).

- [ ] **Step 10: Commit**

```bash
git add lib/main.dart lib/app_root.dart macos/Runner/AppDelegate.swift macos/Runner/MainFlutterWindow.swift
git commit -m "feat: add macOS New Window (Cmd+N)"
```

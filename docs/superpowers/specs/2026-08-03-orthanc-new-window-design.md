# Orthanc New Window (macOS) — Design

## Status

Approved 2026-08-03. Architecture corrected 2026-08-03, before planning: the
originally-approved mechanism (`FlutterEngineGroup` + an `initialRoute` of
`"secondary"`) does not exist on macOS — `FlutterEngineGroup` is iOS/Android
only, confirmed against the installed Flutter 3.41.0 SDK's macOS headers,
which carry no such class. The corrected mechanism (direct `FlutterEngine`
construction per window, `FlutterDartProject.dartEntrypointArguments` for
primary/secondary signaling) is described below; nothing else about the
design — scope, settings-sync approach, lifecycle, error handling — changed.

## Problem

Orthanc runs a single Flutter engine inside one `NSWindow`
(`macos/Runner/MainFlutterWindow.swift`). A user who wants a second,
independent set of panes — a second workspace, watching a different project
or a different batch of Claude Code sessions — has no way to get one short of
quitting and losing the first. This design adds a "New Window" action on
macOS: a second (third, fourth, …) OS window, each holding its own
independent workspace, all sharing the same persisted settings.

Windows and Linux are untouched — Orthanc already has no Linux target, and
this design does not extend to Windows in this pass.

## Scope

**In scope:**

- A "New Window" item (`Cmd+N`) in the existing `PlatformMenuBar` "Orthanc"
  menu, macOS only.
- Native window/engine creation: a new `NSWindow` + `FlutterViewController`
  backed by a freshly spawned `FlutterEngine`, with all existing plugins
  registered on it.
- Every window runs a full, independent `OrthancApp` → `AppRoot` →
  `WorkspaceView` tree — its own panes, its own pty sessions, its own
  lifecycle. Closing one window never affects another.
- Live settings sync: a settings change saved in one window is picked up by
  every other open window without requiring it to be reopened.
- Update-check/update-note-banner runs only in the primary window (the one
  open at launch), not in windows opened via "New Window."

**Out of scope (named, not silently dropped):**

- Windows support. "New Window" is a macOS-only menu item; no equivalent is
  added to the Windows title-bar system menu.
- Copying the calling window's pane layout into the new window. A new window
  always starts as a single default pane, identical to a fresh launch.
- Any cross-window feature beyond settings — panes, sessions, and layout
  never cross a window boundary.
- A "Window" menu for cycling/arranging open windows. Standard macOS
  Cmd+`/Cmd+~ window cycling and the Window menu Cocoa provides by default
  are relied on as-is; nothing custom is added.

## Architecture

### Native window/engine creation — `macos/Runner`

macOS has no `FlutterEngineGroup` (that class is iOS/Android-only). Instead,
`AppDelegate` builds each additional window's `FlutterEngine` directly, the
documented macOS multi-window pattern: construct the engine explicitly, run
it, *then* wrap it in a `FlutterViewController`:

```swift
let project = FlutterDartProject()
project.dartEntrypointArguments = ["secondary"]
let engine = FlutterEngine(name: "orthanc-secondary", project: project)
engine.run(withEntrypoint: nil)

let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
RegisterGeneratedPlugins(registry: controller)
let window = NSWindow(contentViewController: controller)
window.makeKeyAndOrderFront(nil)
```

`RegisterGeneratedPlugins` runs per engine — the same call
`MainFlutterWindow.awakeFromNib` already makes for the primary window — so
`flutter_pty`, `path_provider`, `shared_preferences`, `package_info_plus`,
`auto_updater`, and `url_launcher` all work identically in every window.

The existing `orthanc/system_menu` `MethodChannel` (already used for
`openSettings`) gains a second method, `newWindow`. Unlike `openSettings`
(native calling Dart), this direction is Dart calling native: the "New
Window" menu item's `onSelected` invokes it. The handler is registered on
every window's engine — the primary window's (from
`MainFlutterWindow.awakeFromNib`) and every secondary window's (from the
`createSecondaryWindow()` routine above, immediately after that window's own
engine is created) — so `Cmd+N` works identically from any open window, not
only the first.

`engine.run(withEntrypoint: nil)` reruns the app's normal Dart `main()` from
scratch. No entrypoint-dispatch logic is needed on the Dart side — every
window's Dart code is the same `main()` → `OrthancApp` tree used today.

### Primary-window detection — `lib/main.dart`

`FlutterDartProject.dartEntrypointArguments`, set above only for secondary
windows, arrives as `main()`'s own `args: List<String>` parameter — the
standard Dart command-line-arguments mechanism, synchronous and available
before a single line of `main()` runs, no async round-trip needed:

```dart
Future<void> main(List<String> args) async {
  final isPrimaryWindow = !args.contains('secondary');
  ...
}
```

A normal launch (primary window) passes no such argument — `args` defaults
to the process's real command-line arguments, which never contain
`"secondary"` — so `MainFlutterWindow` needs no matching change for this
part; `isPrimaryWindow` is `true` there with zero native code.
`isPrimaryWindow` threads into `OrthancApp` → `AppRoot`. `AppRoot` only calls
`_checkForUpdate()` / `_showUpdateNoteIfAny()` when `isPrimaryWindow` is
true; a secondary window's `AppRoot` renders `WorkspaceView` directly with no
update machinery.

### Settings live sync — `lib/settings_store.dart`, `lib/settings_watch.dart` (new)

`readSettings()`/`writeSettings()` are unchanged — `writeSettings()`
already writes via temp-file + atomic rename, which produces a clean
modify-then-rename sequence for a watcher to react to.

A new pure-ish unit, `lib/settings_watch.dart`, owns the reconciliation
decision:

```dart
/// Returns [next] only when it differs from [current]; otherwise returns
/// [current] unchanged, so a caller can skip a needless ValueNotifier
/// update (and the rebuild it would trigger) on a no-op file event.
Settings reconcileSettings({required Settings current, required Settings next});
```

`Settings` has no `==` override today (a plain class, compared by identity),
and this design does not add one — two independently-parsed instances would
never be identity-equal even with identical fields. `reconcileSettings()`
instead compares `executablePath`, `colorScheme`, `fontFamily`, and
`fontSize` directly, field by field.

`main()` starts a `File.watch(settings.json path)` stream (macOS: FSEvents)
after the initial `readSettings()` call. On a modify event, it re-reads the
file, runs it through `reconcileSettings()`, and — only on an actual change
— updates the app-wide `ValueNotifier<Settings>` that panes already observe
for font/color-scheme. No new IPC or cross-window messaging is added; every
window is simply watching the same file independently.

An open Settings dialog is unaffected by another window's save — it holds
its own local edit-buffer state (as it does today) until Save is pressed,
so a live reload from elsewhere never clobbers in-progress unsaved edits.

### Window lifecycle

A created `NSWindow` needs a strong reference kept somewhere for as long as
it's open — nothing else retains it, and without one it would deallocate
(and silently close) the moment `createSecondaryWindow()` returns.
`AppDelegate` keeps a `private var secondaryWindows: [NSWindow] = []`,
appends each new window to it, and removes it again on that window's
`NSWindow.willCloseNotification` — so memory is released promptly when a
window closes rather than accumulating for the life of the app.

`AppDelegate.applicationShouldTerminateAfterLastWindowClosed` is unchanged
(`return true`) — it already fires only once zero windows remain, which
extends correctly from "the one window" to "the last of N windows." Closing
any single window tears down just that window's `NSWindow`, `FlutterEngine`,
and everything under it (panes, sessions, ptys) — independent of any other
open window.

## Data flow

```
Cmd+N (any window) → orthanc/system_menu.newWindow
    → FlutterDartProject(dartEntrypointArguments: ["secondary"])
    → FlutterEngine(...).run() → new FlutterViewController + NSWindow
    → RegisterGeneratedPlugins + configureSystemMenuChannel
    → runs main(args) fresh → isPrimaryWindow = false
    → OrthancApp → AppRoot (no update-check) → WorkspaceView (one default pane)
```

```
Window A: Settings dialog Save → writeSettings() (temp file + rename)
    → filesystem modify event
Window B (and C, D, …): File.watch fires
    → readSettings() → reconcileSettings(current, next)
    → differs → ValueNotifier<Settings> updated → panes re-render live
```

## Error handling

- **Engine/window creation fails** (rare — resource exhaustion): the
  `newWindow` channel call fails silently; no error dialog. Matches the
  app's existing fail-silent precedent for rare, low-stakes, easily-retried
  failures (`_checkForUpdate` in `app_root.dart`). The user can just press
  `Cmd+N` again.
- **Settings file-watch stream errors, or a read lands mid-rename**: caught
  and ignored. The next filesystem event, or the next window's own startup
  read, resyncs state. No user-facing error.
- **Corrupt/unparseable settings.json observed mid-watch**: handled exactly
  as `readSettings()` already handles it at startup — falls back to the
  prior in-memory `Settings` rather than propagating a parse failure.

## Testing

- `settings_watch_test.dart` (new) — `reconcileSettings()` is pure: unit
  tested for "differs ⇒ returns next," "identical ⇒ returns current
  unchanged" (including field-by-field equality, not just reference
  equality).
- The native engine/window plumbing, the live multi-window settings sync,
  and per-window pty independence cannot be exercised by `flutter test` —
  same limitation the README already names for the pty/terminal wiring —
  and are confirmed by hand on macOS: open a new window and confirm it has
  its own independent pane/session; change a setting in one window and
  confirm the other's rendered font/color updates live without reopening
  it; close one window and confirm the other is unaffected; quit the last
  window and confirm the app terminates.
- `isPrimaryWindow` gating the update-check is a one-line conditional,
  trivial enough to leave to the manual walk above rather than a dedicated
  widget test.

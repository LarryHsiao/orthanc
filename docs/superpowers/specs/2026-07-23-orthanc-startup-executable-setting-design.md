# Orthanc Startup Executable Setting — Design

## Status

Approved 2026-07-23. First concrete setting under a new, general preferences
mechanism — see [Future settings](#future-settings) for how later settings
extend this without redesign.

## Problem

Every pane spawns a plain shell (`shellCommand()` in `lib/shell_command.dart`)
and the user types `claude` into it by hand. There is no way to configure what
actually launches, and no settings/preferences mechanism of any kind exists in
the app — no persistence, no UI, nothing. This design adds both: a small,
extensible preferences store, and its first setting — an override path for the
executable each new pane spawns.

`lib/claude_command.dart` (`resolveClaudeCommand()`, `knownClaudePaths()`) is
pre-existing dead code from Milestone 0, superseded by Milestone 1's plain-shell
approach and currently uncalled from anywhere in `lib/`. This design does not
touch it, revive it, or route through it — it is a separate concern, named
here only so its absence from this plan is not mistaken for an oversight.

## Scope

**In scope:**

- A `Settings` model holding one field today (`executablePath`), persisted as
  JSON under the platform's application-support directory.
- A Settings dialog with a path field, save/cancel/reset, and validation.
- Wiring so `Sessions.spawn()` uses the configured path when set, falling back
  to today's `shellCommand()` detection when unset.
- One native entry point per platform to open the dialog (see
  [Entry points](#entry-points)).

**Out of scope (named, not silently dropped):**

- Per-pane executable overrides. The setting is global — one value, applied to
  every pane opened after a save. Milestone 1 explicitly deferred per-pane
  commands; this design does not reopen that.
- `claude_command.dart`'s dead code, as above.
- Any settings beyond the startup executable path. The mechanism is built to
  extend (see [Future settings](#future-settings)), but no other setting is
  implemented in this pass.
- A file-picker dialog. The path field is plain text entry only.

## Architecture

### Settings model — `lib/settings.dart`

```dart
class Settings {
  const Settings({this.executablePath});
  final String? executablePath;
}

Map<String, dynamic> settingsToJson(Settings settings);
Settings settingsFromJson(Map<String, dynamic> json);
```

Pure data and pure (de)serialization. No I/O, no platform calls. `executablePath`
is `null` (or an empty string is treated identically to `null` throughout) when
no override is set.

### Persistence — `lib/settings_store.dart`

```dart
File settingsFile({required Directory supportDir});
Settings readSettings({required File file});
void writeSettings(Settings settings, {required File file});
```

Each function takes the directory/file explicitly rather than resolving it
internally — the same shape as `claude_command.dart`'s `exists:` injection —
so tests point these at a temp directory and never touch the real
application-support path or a live engine.

`supportDir` itself is resolved exactly once, in `main()`, via the new
`path_provider` dependency's `getApplicationSupportDirectory()`, and the
resulting `Settings` is loaded before `runApp()`. `readSettings()` returns
`const Settings()` (no override) when the file does not yet exist — first run
needs no migration step.

### Applying the setting — `lib/shell_command.dart`

`shellCommand()` gains an optional parameter:

```dart
String shellCommand({
  required bool isWindows,
  required Map<String, String> environment,
  String? configured,
});
```

A non-null, non-empty `configured` value is returned as-is; otherwise today's
detection logic runs exactly as it does now. `Sessions.spawn()` reads the
app-wide loaded `Settings.executablePath` and passes it through — no per-pane
plumbing, since the setting is global.

Effect timing: saving updates the in-memory `Settings` and the on-disk file
immediately. Only panes opened *after* that point see the new value; panes
already running are undisturbed — consistent with how `Sessions.spawn()`
already resolves its command once, at spawn time, per pane.

### Validation — `lib/settings_validation.dart`

```dart
bool executableExists(String path, {required bool Function(String) exists});
```

Pure and injectable, mirroring `claude_command.dart`'s existing pattern. The
dialog calls this before allowing Save; a path that fails the check keeps the
previously-saved value and shows an inline error. An empty field is always
valid (it means "use the default") and is never checked for existence.

### Settings dialog — `lib/settings_dialog.dart`

A Material `Dialog` with:

- A single-line text field, pre-filled with the current `executablePath` or
  showing an italic placeholder (`default: <detected path>`) when unset.
- **Save** — disabled whenever the current field content fails
  `executableExists()` (and is non-empty); on success, writes via
  `writeSettings()` and updates the app-wide in-memory `Settings`, then closes.
- **Cancel** — discards edits, closes.
- **Reset to default** — clears the field to empty (disabled when the field is
  already empty); still requires a subsequent Save to persist.
- Inline error text under the field when the current content is invalid,
  naming the problem plainly (see the wireframe's validation state).

See `wireframe-orthanc-settings.html` (rendered via `/henneth`) for the visual
layout in both data states plus the validation state.

### Entry points

No shared chrome is added — panes keep filling the whole window, exactly as
today. Each platform gets its own idiomatic entry point into one shared
`showSettingsDialog(BuildContext)`:

- **macOS** — `PlatformMenuBar` adds a standard "Settings…" (⌘,) item to the
  app's native menu bar.
- **Windows** — a small platform-channel addition under `windows/runner`
  appends a "Settings…" item to the title bar's native system menu
  (`GetSystemMenu` + handling the resulting `WM_SYSCOMMAND`), invoked over a
  method channel back into Flutter.

Both call the same dialog; there is exactly one dialog implementation and one
settings mechanism behind two platform-native doors.

## Data flow

```
main() → resolve supportDir → readSettings() → Settings held app-wide
                                                       │
                                        Sessions.spawn() reads
                                        Settings.executablePath
                                                       │
                                          shellCommand(configured: …)
                                                       │
                                              Session.executable
```

```
User opens Settings (native menu / system menu)
     → showSettingsDialog()
     → edits path field
     → Save → executableExists()? 
          ├─ yes → writeSettings() + update in-memory Settings → close
          └─ no  → inline error, keep prior value, dialog stays open
```

## Error handling

- **Missing settings file** (first run, or file deleted by hand): treated as
  `const Settings()` — no override, no crash, no dialog shown unprompted.
- **Corrupt/unparseable JSON**: `readSettings()` falls back to
  `const Settings()` rather than throwing — a hand-edited or truncated file
  must not block app startup.
- **Invalid path at save time**: rejected in the dialog per
  [Validation](#validation); never written to disk.
- **Valid-looking path that later fails to spawn** (permissions, deleted after
  save): out of scope for this design — `Session`'s existing exit-code
  handling already surfaces "the process exited with exit code N" in the
  pane, which is where this failure would land, same as any other spawn
  failure today.

## Testing

Every new unit is a pure function or an I/O function taking its target
explicitly, so all of the following run with no engine and no real
filesystem/app-support path — the pattern `claude_command_test.dart` already
established:

- `settings_test.dart` — JSON round-trip (including the "missing field ⇒
  null" and "empty string ⇒ treated as null" cases).
- `settings_store_test.dart` — read/write against a temp `Directory`; missing
  file ⇒ default `Settings`; corrupt JSON ⇒ default `Settings`.
- `settings_validation_test.dart` — `executableExists()` against a faked
  `exists:`.
- `shell_command_test.dart` — extended for the new `configured` param: set
  ⇒ returned as-is; unset/empty ⇒ existing behavior unchanged.

The dialog's widget-level behavior (field state, button enablement, error
display) is covered by `flutter_test` widget tests. The two native menu entry
points cannot be exercised by `flutter test` — same limitation the README
already names for pty/terminal wiring — and are confirmed by hand on each
platform during the walk.

## Future settings

Nothing here is startup-executable-specific by name beyond the one field:
`Settings` gains new nullable fields, `settingsToJson`/`settingsFromJson`
extend accordingly, and the dialog gains new fields in the same `Dialog` —
no new persistence mechanism, no new entry point, no new dialog shape. This
design intentionally stops at exactly one setting; do not add fields,
sections, or speculative hooks for settings not yet named.

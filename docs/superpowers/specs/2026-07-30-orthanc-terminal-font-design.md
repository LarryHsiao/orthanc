# Orthanc Terminal Font Setting — Design

## Status

Approved 2026-07-30. Third setting under the preferences mechanism the
[startup executable setting](2026-07-23-orthanc-startup-executable-setting-design.md)
introduced. The color scheme setting (`b76c57a`, `55a3561`) already extended
that mechanism with a closed-enum field and a live preview; it shipped
without its own design doc, so this design follows its shape as read from
the code rather than from a prior spec.

## Problem

Every pane's `TerminalView` renders with xterm's own bare defaults —
`fontFamily: 'monospace'` at `fontSize: 13.0` — set nowhere in this codebase.
The only font-related code that exists today is `fontFamilyFallback` in
`lib/pane_view.dart`, added to fix Nerd Font glyph and emoji-vs-dingbat
rendering (see `ac68619`, `4ebb3de`); it is a *fallback* chain for glyph
coverage, not a user-facing choice. There is no way to pick a primary font
family or size. This design adds both as a fourth and fifth `Settings` field,
alongside the existing executable path and color scheme.

## Scope

**In scope:**

- Two new `Settings` fields: `fontFamily` (a closed `TerminalFontFamily`
  enum, mirroring `TerminalColorScheme`) and `fontSize` (`double?`, null
  meaning "use xterm's own default").
- A `TerminalFontFamily` picklist in the Settings dialog, plus a font-size
  numeric field with `−`/`+` stepper buttons, clamped to 8–32pt.
- A merged live preview: the existing `ColorSchemePreview` widget is
  generalized into `TerminalPreview`, taking scheme, font family, and font
  size together, so one sample terminal shows the combined pending picks.
- A "Reset font" action, placed at the font block's own bottom-right
  (beside the size stepper) rather than in the dialog's bottom actions row —
  disabled when family is already `defaultFamily` and size is already null.
- Wiring so every open pane re-renders with the saved font immediately on
  Save — the same live-apply behavior the color scheme setting already has.

**Out of scope (named, not silently dropped):**

- Any change to `fontFamilyFallback` itself. The fallback chain that fixes
  Nerd Font glyph and dingbat-vs-emoji rendering is untouched; the new
  primary `fontFamily` sits in front of it, and an uninstalled pick still
  degrades safely through that same chain rather than showing tofu.
- Per-pane font overrides. Global setting only, same constraint the
  executable-path and color-scheme settings already carry.
- Live installed-font detection/validation. The family picklist is a fixed,
  curated set of common cross-platform coding fonts; there is no OS
  font-enumeration check, and picking a font absent on the user's system is
  not treated as an error — it silently resolves through
  `fontFamilyFallback`, identical to how an unrecognized `fontFamily` string
  already behaves in Skia today.
- A font-file picker or bundling any font with the app. Every entry names a
  font Orthanc expects to already be installed.

## Architecture

### Font family model — `lib/settings.dart` and new `lib/terminal_font_families.dart`

```dart
// settings.dart
enum TerminalFontFamily {
  defaultFamily,
  hackNerdFontMono,
  menlo,
  monaco,
  consolas,
  jetBrainsMono,
  firaCode,
  cascadiaCode,
  courierNew,
}

class Settings {
  const Settings({
    this.executablePath,
    this.colorScheme = TerminalColorScheme.defaultScheme,
    this.fontFamily = TerminalFontFamily.defaultFamily,
    this.fontSize,
  });

  final String? executablePath;
  final TerminalColorScheme colorScheme;
  final TerminalFontFamily fontFamily;
  final double? fontSize;
}
```

`fontFamily` follows the `colorScheme` pattern (closed set ⇒ enum,
non-nullable, `defaultFamily` as the zero value) rather than the
`executablePath` pattern (open value ⇒ nullable string), because the
picklist is a fixed set of named options, not free text. `fontSize` follows
the *opposite* precedent — `executablePath`'s nullable-means-default — because
size is a scalar with one sane default, not a closed set worth enumerating.

`settingsToJson`/`settingsFromJson` extend exactly as `colorScheme` already
does: `fontFamily.name` round-trips via a `_fontFamilyFromName` lookup
(`orElse` ⇒ `defaultFamily`, same shape as `_colorSchemeFromName`); `fontSize`
serializes as a nullable `double` and deserializes with a plain `as double?`
cast (no normalization function needed — unlike `executablePath`, there is no
"empty string means null" ambiguity for a numeric field).

```dart
// terminal_font_families.dart
String? terminalFontFamilyName(TerminalFontFamily family);
String terminalFontFamilyLabel(TerminalFontFamily family);
```

`terminalFontFamilyName` mirrors `terminalThemeFor`'s shape: a `switch`
mapping every enum value to the literal font-family string `TerminalStyle`
should receive, except `defaultFamily`, which maps to `null` (letting
`TerminalStyle`'s own `fontFamily` default of `'monospace'` apply, unchanged
from today). `terminalFontFamilyLabel` mirrors `terminalColorSchemeLabel`
exactly — the dropdown's display string per value (e.g. `jetBrainsMono` ⇒
`'JetBrains Mono'`).

### Applying the setting — `lib/pane_view.dart`, `lib/split_view.dart`, `lib/workspace_view.dart`

`workspace_view.dart`'s existing `ValueListenableBuilder<Settings>` (build
method) already recomputes `theme: terminalThemeFor(settings.colorScheme)`
into `SplitView` on every `Settings` change. It gains two sibling values:

```dart
SplitView(
  ...
  theme: terminalThemeFor(settings.colorScheme),
  fontFamily: terminalFontFamilyName(settings.fontFamily),
  fontSize: settings.fontSize,
  ...
)
```

`SplitView` and `PaneView` both gain matching `String? fontFamily` and
`double? fontSize` parameters, pure passthrough exactly as `theme` already
is today — no new state, no new logic in either widget. `PaneView` forwards
both into `TerminalView`'s `textStyle`:

```dart
textStyle: TerminalStyle(
  fontFamily: widget.fontFamily,  // null ⇒ TerminalStyle's own default
  fontSize: widget.fontSize,      // null ⇒ TerminalStyle's own default
  fontFamilyFallback: [ /* unchanged existing list */ ],
),
```

Because `TerminalStyle`'s constructor defaults (`fontFamily = 'monospace'`,
`fontSize = 13.0`) already activate on a `null` argument, passing `null`
straight through for `defaultFamily`/unset `fontSize` reproduces exactly
today's unconfigured behavior — no separate "is this the default" branching
needed in `PaneView`.

Because this rides the same `ValueListenableBuilder` as `colorScheme`, saving
in the Settings dialog updates every already-open pane's rendering
immediately — panes do not need to be closed and reopened, matching color
scheme's existing live-apply behavior (and unlike `executablePath`, which
only affects panes spawned after the save, since it is read once at
process-spawn time rather than on every build).

### Settings dialog — `lib/settings_dialog.dart` and generalized preview

`_SettingsDialogState` gains a "Terminal font" block, placed after the
existing "Terminal color scheme" block and before the (also generalized)
preview:

- `DropdownButton<TerminalFontFamily>`, same shape as the existing color
  scheme dropdown — `isExpanded: true`, items built from
  `TerminalFontFamily.values` with `terminalFontFamilyLabel()`.
- A font-size row: `−`/`+` `IconButton`s flanking a small numeric `Text`
  (not a raw editable `TextField` — the stepper is the only input surface,
  keeping this a closed, always-valid interaction rather than needing its
  own validation state). Each tap adjusts by 1pt, clamped to `[8, 32]`;
  `−`/`+` disable at the respective bound. Unset (`null`) displays and steps
  from the resolved default (13).
- "Reset font" `TextButton`, laid out at this block's bottom-right (a `Row`
  with `MainAxisAlignment.spaceBetween` pairing it against the stepper, not
  a sixth entry in the dialog's bottom actions row) — disabled when family
  is already `defaultFamily` **and** size is already `null`; resets both
  together in one tap via a new `_resetFont()` method, mirroring
  `_resetColorScheme()`'s shape.

`lib/color_scheme_preview.dart` is renamed `lib/terminal_preview.dart`; its
`ColorSchemePreview` class is renamed `TerminalPreview` and gains
`fontFamily`/`fontSize` parameters alongside its existing `scheme`, forwarded
into the same non-interactive `TerminalView`'s `textStyle` exactly as
`PaneView` does. The existing sample content (colored
`ls` output, an error line, a git-branch accent row) is left unchanged — it
already exercises the glyphs a font pick most needs judged against. Every
existing call site (`ColorSchemePreview(scheme: _colorScheme)`) becomes
`TerminalPreview(scheme: _colorScheme, fontFamily: ..., fontSize: ...)`.

The dialog's bottom actions row is unaffected by this design — it stays at
the four buttons already verified to fit (`Reset to default`, `Reset
scheme`, `Cancel`, `Save`) — since `Reset font` lives inside the font block
instead. This was a deliberate layout decision after the reset-scheme
button's addition proved the actions row is width-constrained (see
`af8f083`); a fifth button there was not re-attempted.

See `wireframe-settings-dialog-font.html` (rendered via `/henneth`) for the
visual layout in both the all-default and a custom-pick state.

## Data flow

```
Settings (fontFamily, fontSize)
        │
        ├─ terminalFontFamilyName(fontFamily) ──┐
        │                                        │
workspace_view.dart's ValueListenableBuilder ────┼──▶ SplitView(fontFamily, fontSize, theme)
        │                                        │           │
        └─ fontSize ─────────────────────────────┘           ▼
                                                        PaneView(fontFamily, fontSize, theme)
                                                               │
                                                               ▼
                                              TerminalView(textStyle: TerminalStyle(
                                                fontFamily, fontSize, fontFamilyFallback))
```

```
User opens Settings
     → showSettingsDialog()
     → picks family (dropdown) / adjusts size (stepper)
     → TerminalPreview re-renders with the pending pick
     → Save → writeSettings() + update in-memory Settings → close
          → ValueListenableBuilder rebuilds every open pane with the new font
```

## Error handling

- **Missing `fontFamily`/`fontSize` keys** (settings file written by an
  older version): `_fontFamilyFromName(null)` falls to `defaultFamily` via
  its `orElse`, exactly as `_colorSchemeFromName` already does; `fontSize`
  casts `null` straight through as `as double?`. No migration step, no
  crash — same posture the existing fields already take on an old file.
- **Corrupt/unparseable JSON**: unchanged — `readSettings()` already falls
  back to `const Settings()` wholesale, which now also carries the new
  fields' defaults.
- **Font not installed on the user's system**: not an error state. Skia's
  own font resolution falls through `fontFamilyFallback` when the requested
  `fontFamily` is unavailable, so the pane renders with the fallback chain's
  first available match rather than tofu or a crash — the same safety
  property that already protects every entry in `fontFamilyFallback` today.
- **Font size at the clamp boundary**: the stepper buttons simply disable at
  8 and 32; there is no out-of-range state to reject, since the UI cannot
  produce one.

## Testing

- `settings_test.dart` — extended for `fontFamily`/`fontSize` JSON
  round-trip, including "missing key ⇒ default" for both fields (mirroring
  the existing `colorScheme` coverage).
- `terminal_font_families_test.dart` (new) — exhaustiveness of
  `terminalFontFamilyName`'s and `terminalFontFamilyLabel`'s `switch`
  statements over every `TerminalFontFamily` value, mirroring whatever
  `terminal_color_schemes_test.dart` already covers for the color-scheme
  equivalents.
- `settings_dialog_test.dart` — extended with: family dropdown prefilled
  from current selection; size stepper prefilled/clamped at 8 and 32;
  preview reflects the pending family/size before Save; "Reset font"
  disabled when already default, resets both fields and re-disables on tap;
  Save persists both fields.
- `color_scheme_preview_test.dart` — renamed `terminal_preview_test.dart`,
  extended to cover `TerminalPreview`'s font parameters alongside its
  existing scheme coverage.
- As with the color-scheme setting, live-apply-to-open-panes is not
  something `flutter test` can exercise end-to-end (no real pty session in
  widget tests); confirmed by hand during the walk, same as the executable
  path setting's native-menu entry points were.

## Future settings

Nothing here is font-specific beyond these two fields. `Settings` gains two
more fields; `settingsToJson`/`settingsFromJson` extend accordingly; the
dialog gains one more block. No new persistence mechanism, no new dialog,
no new live-apply plumbing beyond what `colorScheme` already established.
This design stops at font family and size; do not add line-height, ligature
toggles, or other typography knobs not named here.

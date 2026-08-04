import 'settings.dart';

/// Matches xterm's own TerminalStyle defaults (`_kDefaultFontFamily` /
/// `_kDefaultFontSize` in the pinned fork, unexported so not importable) —
/// what every pane already renders with today, unconfigured. TerminalStyle's
/// fontFamily/fontSize fields are non-nullable, so these stand in for a null
/// argument, which would not compile.
const defaultTerminalFontFamily = 'monospace';
const defaultTerminalFontSize = 13.0;

/// xterm's built-in fallback list is Linux/Android-flavored and omits Hack
/// Nerd Font Mono, so the Private-Use-Area glyphs shell tools (lsd,
/// oh-my-posh, ...) use for icons render as tofu unless named explicitly
/// here — a no-op fallback entry on a machine that lacks it.
///
/// Apple Color Emoji / Segoe UI Emoji are deliberately absent: both claim
/// dingbat codepoints that also have a plain-text glyph (Claude Code's
/// spinner frames — ✢ ✳ ✻ ✽ — and its ⏺ paragraph bullet included), and
/// being first in the list would win the match and render them in color
/// instead of the monochrome glyph a native terminal shows.
///
/// The trailing entries below are copied verbatim from the fork's private
/// _kDefaultFontFamilyFallback (unexported, so not importable) —
/// lib/src/ui/terminal_text_style.dart at the pinned pubspec.yaml ref.
/// Re-sync if that list changes upstream. Shared between every pane
/// (PaneView) and the Settings dialog's live preview (TerminalPreview), so
/// the preview can never show glyph rendering a real pane wouldn't.
const terminalFontFamilyFallback = [
  'Hack Nerd Font Mono',
  'Menlo',
  'Monaco',
  'Consolas',
  'Liberation Mono',
  'Courier New',
  'Noto Sans Mono CJK SC',
  'Noto Sans Mono CJK TC',
  'Noto Sans Mono CJK KR',
  'Noto Sans Mono CJK JP',
  'Noto Sans Mono CJK HK',
  // Covers Claude Code's ⏺ paragraph bullet (U+23FA, Miscellaneous
  // Technical) in monochrome. None of the fonts above carry that glyph on
  // stock macOS, so without this entry the search falls through the whole
  // list and the OS's own fallback cascade lands on Apple Color Emoji
  // anyway — the exact substitution this file's fonts are meant to avoid.
  // STIX Two Math ships as part of macOS's own default font set.
  'STIX Two Math',
  'Noto Color Emoji',
  'Noto Sans Symbols',
  'monospace',
  'sans-serif',
];

/// The actual font-family string a persisted [TerminalFontFamily] maps to,
/// for use as [TerminalStyle.fontFamily].
String terminalFontFamilyName(TerminalFontFamily family) {
  return switch (family) {
    TerminalFontFamily.defaultFamily => defaultTerminalFontFamily,
    TerminalFontFamily.hackNerdFontMono => 'Hack Nerd Font Mono',
    TerminalFontFamily.menlo => 'Menlo',
    TerminalFontFamily.monaco => 'Monaco',
    TerminalFontFamily.consolas => 'Consolas',
    TerminalFontFamily.jetBrainsMono => 'JetBrains Mono',
    TerminalFontFamily.firaCode => 'Fira Code',
    TerminalFontFamily.cascadiaCode => 'Cascadia Code',
    TerminalFontFamily.courierNew => 'Courier New',
  };
}

/// The label a font family picker shows the user.
String terminalFontFamilyLabel(TerminalFontFamily family) {
  return switch (family) {
    TerminalFontFamily.defaultFamily => 'Default',
    TerminalFontFamily.hackNerdFontMono => 'Hack Nerd Font Mono',
    TerminalFontFamily.menlo => 'Menlo',
    TerminalFontFamily.monaco => 'Monaco',
    TerminalFontFamily.consolas => 'Consolas',
    TerminalFontFamily.jetBrainsMono => 'JetBrains Mono',
    TerminalFontFamily.firaCode => 'Fira Code',
    TerminalFontFamily.cascadiaCode => 'Cascadia Code',
    TerminalFontFamily.courierNew => 'Courier New',
  };
}

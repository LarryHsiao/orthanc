import 'settings.dart';

/// Matches xterm's own TerminalStyle defaults (`_kDefaultFontFamily` /
/// `_kDefaultFontSize` in the pinned fork, unexported so not importable) —
/// what every pane already renders with today, unconfigured. TerminalStyle's
/// fontFamily/fontSize fields are non-nullable, so these stand in for a null
/// argument, which would not compile.
const defaultTerminalFontFamily = 'monospace';
const defaultTerminalFontSize = 13.0;

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

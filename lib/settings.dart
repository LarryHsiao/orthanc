/// The named terminal color schemes a user may pick in Settings. The actual
/// xterm TerminalTheme each maps to lives in terminal_color_schemes.dart —
/// this file only needs the closed set of identifiers a preference can hold.
enum TerminalColorScheme {
  defaultScheme,
  whiteOnBlack,
  dracula,
  solarizedDark,
  solarizedLight,
  monokai,
  oneDark,
  nord,
  gruvboxDark,
}

/// The named terminal font families a user may pick in Settings. The actual
/// font-family string each maps to lives in terminal_font_families.dart —
/// this file only needs the closed set of identifiers a preference can hold.
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

/// The default scrollback cap for a session's terminal, in lines — both
/// [Settings.historyLines]'s default and the value the dialog's hint text
/// shows.
const defaultHistoryLines = 10000;

/// The user's persisted preferences.
class Settings {
  const Settings({
    this.executablePath,
    this.colorScheme = TerminalColorScheme.defaultScheme,
    this.fontFamily = TerminalFontFamily.defaultFamily,
    this.fontSize,
    this.startQuakeAtLogin = false,
    this.historyLines = defaultHistoryLines,
  });

  final String? executablePath;
  final TerminalColorScheme colorScheme;
  final TerminalFontFamily fontFamily;
  final double? fontSize;
  final bool startQuakeAtLogin;

  /// How many lines of scrollback each new pane's terminal keeps. Only
  /// newly-spawned sessions pick up a change — see [Session.historyLines].
  final int historyLines;
}

/// A blank path means "use the default" — normalized to null wherever a
/// path is read from disk or from user input.
String? normalizeExecutablePath(String? path) {
  final trimmed = path?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

Map<String, dynamic> settingsToJson(Settings settings) {
  return {
    'executablePath': settings.executablePath,
    'colorScheme': settings.colorScheme.name,
    'fontFamily': settings.fontFamily.name,
    'fontSize': settings.fontSize,
    'startQuakeAtLogin': settings.startQuakeAtLogin,
    'historyLines': settings.historyLines,
  };
}

Settings settingsFromJson(Map<String, dynamic> json) {
  return Settings(
    executablePath: normalizeExecutablePath(json['executablePath'] as String?),
    colorScheme: _colorSchemeFromName(json['colorScheme'] as String?),
    fontFamily: _fontFamilyFromName(json['fontFamily'] as String?),
    fontSize: (json['fontSize'] as num?)?.toDouble(),
    startQuakeAtLogin: json['startQuakeAtLogin'] as bool? ?? false,
    historyLines: json['historyLines'] as int? ?? defaultHistoryLines,
  );
}

TerminalColorScheme _colorSchemeFromName(String? name) {
  return TerminalColorScheme.values.firstWhere(
    (scheme) => scheme.name == name,
    orElse: () => TerminalColorScheme.defaultScheme,
  );
}

TerminalFontFamily _fontFamilyFromName(String? name) {
  return TerminalFontFamily.values.firstWhere(
    (family) => family.name == name,
    orElse: () => TerminalFontFamily.defaultFamily,
  );
}

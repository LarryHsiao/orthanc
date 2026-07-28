/// The named terminal color schemes a user may pick in Settings. The actual
/// xterm TerminalTheme each maps to lives in terminal_color_schemes.dart —
/// this file only needs the closed set of identifiers a preference can hold.
enum TerminalColorScheme {
  defaultScheme,
  whiteOnBlack,
  dracula,
  solarizedDark,
  monokai,
  oneDark,
}

/// The user's persisted preferences.
class Settings {
  const Settings({
    this.executablePath,
    this.colorScheme = TerminalColorScheme.defaultScheme,
  });

  final String? executablePath;
  final TerminalColorScheme colorScheme;
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
  };
}

Settings settingsFromJson(Map<String, dynamic> json) {
  return Settings(
    executablePath: normalizeExecutablePath(json['executablePath'] as String?),
    colorScheme: _colorSchemeFromName(json['colorScheme'] as String?),
  );
}

TerminalColorScheme _colorSchemeFromName(String? name) {
  return TerminalColorScheme.values.firstWhere(
    (scheme) => scheme.name == name,
    orElse: () => TerminalColorScheme.defaultScheme,
  );
}

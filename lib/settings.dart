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

/// The seed for [Settings.linkPreviewNever]: loopback and private-range
/// addresses, so hovering a link to a local service never sends it a
/// request. Plain data — the user may edit or clear it in Settings.
const defaultLinkPreviewNever = [
  r'^https?://(localhost|127\.|10\.|192\.168\.)',
];

/// The user's persisted preferences.
class Settings {
  const Settings({
    this.executablePath,
    this.colorScheme = TerminalColorScheme.defaultScheme,
    this.fontFamily = TerminalFontFamily.defaultFamily,
    this.fontSize,
    this.startQuakeAtLogin = false,
    this.historyLines = defaultHistoryLines,
    this.linkPreviewEnabled = false,
    this.linkPreviewNever = defaultLinkPreviewNever,
    this.linkPreviewOnly = const [],
  });

  final String? executablePath;
  final TerminalColorScheme colorScheme;
  final TerminalFontFamily fontFamily;
  final double? fontSize;
  final bool startQuakeAtLogin;

  /// How many lines of scrollback each new pane's terminal keeps. Only
  /// newly-spawned sessions pick up a change — see [Session.historyLines].
  final int historyLines;

  /// Whether hovering a link may fetch its page for a preview card. Off by
  /// default: the fetch reveals the user's IP to the linked site.
  final bool linkPreviewEnabled;

  /// Regex patterns, matched against the full URL; a match means "never
  /// preview". Wins over [linkPreviewOnly].
  final List<String> linkPreviewNever;

  /// Regex patterns, matched against the full URL. When non-empty, only a
  /// URL matching at least one is previewed; empty means "any".
  final List<String> linkPreviewOnly;
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
    'linkPreviewEnabled': settings.linkPreviewEnabled,
    'linkPreviewNever': settings.linkPreviewNever,
    'linkPreviewOnly': settings.linkPreviewOnly,
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
    linkPreviewEnabled: json['linkPreviewEnabled'] as bool? ?? false,
    linkPreviewNever: _patternList(
      json['linkPreviewNever'],
      fallback: defaultLinkPreviewNever,
    ),
    linkPreviewOnly: _patternList(json['linkPreviewOnly'], fallback: const []),
  );
}

/// Decodes a persisted pattern list. A missing or non-list value takes
/// [fallback]; a real list keeps only its string entries, so an explicit
/// empty list stays empty — the user clearing the seeded list is a choice,
/// not a missing field.
List<String> _patternList(Object? raw, {required List<String> fallback}) {
  if (raw is! List) return fallback;
  return raw.whereType<String>().toList(growable: false);
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

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

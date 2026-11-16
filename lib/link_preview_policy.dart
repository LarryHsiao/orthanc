import 'settings.dart';

/// Whether hovering [url] may fetch its page for a preview card.
///
/// Off unless [Settings.linkPreviewEnabled]. A [Settings.linkPreviewNever]
/// match always blocks; when [Settings.linkPreviewOnly] is non-empty, only a
/// match against it lets the link through. A pattern that is not a valid
/// regex fails closed — no preview — since a mistyped blocklist entry must
/// never be read as "nothing is blocked".
bool shouldPreview(String url, Settings settings) {
  if (!settings.linkPreviewEnabled) return false;
  final never = _compile(settings.linkPreviewNever);
  final only = _compile(settings.linkPreviewOnly);
  if (never == null || only == null) return false;
  if (never.any((pattern) => pattern.hasMatch(url))) return false;
  return only.isEmpty || only.any((pattern) => pattern.hasMatch(url));
}

/// Compiles each non-blank line, or returns null when any line is not a
/// valid regex. Blank lines are skipped: an empty pattern matches every URL.
List<RegExp>? _compile(List<String> lines) {
  final patterns = <RegExp>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      patterns.add(RegExp(trimmed));
    } on FormatException {
      return null;
    }
  }
  return patterns;
}

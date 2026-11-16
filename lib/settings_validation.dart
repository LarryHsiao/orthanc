import 'settings.dart';

bool executableExists(String path, {required bool Function(String) exists}) {
  final normalized = normalizeExecutablePath(path);
  if (normalized == null) return true;
  return exists(normalized);
}

const minTerminalFontSize = 8.0;
const maxTerminalFontSize = 32.0;

double clampFontSize(double size) {
  if (size < minTerminalFontSize) return minTerminalFontSize;
  if (size > maxTerminalFontSize) return maxTerminalFontSize;
  return size;
}

const minHistoryLines = 1000;
const maxHistoryLines = 100000;

/// A regex line that does not compile: its 1-based position in the field and
/// the engine's own reason.
typedef PatternError = ({int line, String reason});

/// The patterns in a one-per-line field: each line trimmed, blank ones
/// dropped (an empty pattern would match every URL).
List<String> patternLinesFromText(String text) => text
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

/// The first line of [text] that is not a valid regex, or null when all are.
/// Blank lines are skipped but still counted, so the line number reported
/// matches what the user sees in the field.
PatternError? firstPatternError(String text) {
  final lines = text.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final pattern = lines[index].trim();
    if (pattern.isEmpty) continue;
    try {
      RegExp(pattern);
    } on FormatException catch (error) {
      return (line: index + 1, reason: error.message);
    }
  }
  return null;
}

/// Parses a scrollback line-count entry, returning null when it isn't a
/// whole number within [minHistoryLines, maxHistoryLines] — rejected rather
/// than clamped, the same treatment [executableExists] gives free-text
/// entry, so a mistake shows up in the dialog instead of being silently
/// substituted.
int? parseHistoryLines(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null) return null;
  if (parsed < minHistoryLines || parsed > maxHistoryLines) return null;
  return parsed;
}

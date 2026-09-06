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

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

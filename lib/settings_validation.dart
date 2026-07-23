import 'settings.dart';

bool executableExists(String path, {required bool Function(String) exists}) {
  final normalized = normalizeExecutablePath(path);
  if (normalized == null) return true;
  return exists(normalized);
}

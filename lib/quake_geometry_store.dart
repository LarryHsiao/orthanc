import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

File quakeGeometryFile({required Directory supportDir}) {
  return File(p.join(supportDir.path, 'quake_geometry.json'));
}

/// The persisted size, or null if none is saved yet, the file is corrupt, or
/// its fields are the wrong shape — mirroring `readSettings()`'s "fall back
/// rather than crash" behavior (`settings_store.dart`). Deliberately not a
/// field on `Settings`: that object has two writers (this store has exactly
/// one, the quake process itself), and a Settings dialog left open in any
/// window would otherwise silently revert a resize on save.
({double width, double height})? readQuakeGeometry({required File file}) {
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return null;
    return (
      width: (decoded['width'] as num).toDouble(),
      height: (decoded['height'] as num).toDouble(),
    );
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

/// Writes via a temp file + rename, mirroring `writeSettings()` — a
/// concurrent read never observes a partially-written file.
void writeQuakeGeometry(
  ({double width, double height}) geometry, {
  required File file,
}) {
  file.parent.createSync(recursive: true);
  final tempFile = File('${file.path}.tmp.$pid');
  tempFile.writeAsStringSync(
    jsonEncode({'width': geometry.width, 'height': geometry.height}),
  );
  tempFile.renameSync(file.path);
}

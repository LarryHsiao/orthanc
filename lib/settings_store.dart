import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'settings.dart';

File settingsFile({required Directory supportDir}) {
  return File(p.join(supportDir.path, 'settings.json'));
}

Settings readSettings({required File file}) {
  if (!file.existsSync()) return const Settings();
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) return const Settings();
    return settingsFromJson(decoded);
  } on FormatException {
    return const Settings();
  } on TypeError {
    return const Settings();
  }
}

/// Writes via a temp file + rename so a concurrent read (from another
/// Orthanc instance, or the app's own next launch) never observes a
/// partially-written file — rename is atomic on both POSIX and Windows.
void writeSettings(Settings settings, {required File file}) {
  file.parent.createSync(recursive: true);
  final tempFile = File('${file.path}.tmp.$pid');
  tempFile.writeAsStringSync(jsonEncode(settingsToJson(settings)));
  tempFile.renameSync(file.path);
}

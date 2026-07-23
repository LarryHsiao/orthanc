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

void writeSettings(Settings settings, {required File file}) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(settingsToJson(settings)));
}

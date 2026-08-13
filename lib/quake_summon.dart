import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;

/// The file whose (re)writing tells a running quake instance to reveal
/// itself — the signal an ordinary window sends when it finds the quake
/// lock already held, rather than spawning a duplicate instance.
File quakeSummonFile({required Directory supportDir}) {
  return File(p.join(supportDir.path, 'quake_summon'));
}

/// Signals the running quake instance to show itself. Each call writes a
/// fresh timestamp via the same temp-file + rename idiom as
/// `writeSettings()` (`settings_store.dart`), so a concurrent watcher never
/// observes a partially-written file.
void requestQuakeSummon({required File file}) {
  file.parent.createSync(recursive: true);
  final tempFile = File('${file.path}.tmp.$pid');
  tempFile.writeAsStringSync(clock.now().microsecondsSinceEpoch.toString());
  tempFile.renameSync(file.path);
}

/// Watches for a summon signal on [file] and calls [onSummon] for each one.
///
/// Deletes the file once handled, so a sentinel left over from a race — two
/// ordinary windows probing at once — self-heals instead of re-triggering a
/// summon after this instance is already showing.
///
/// Mirrors `watchSettingsFile()`'s directory-watch idiom
/// (`settings_watch.dart`), including watching for [FileSystemEvent.delete]
/// alongside [FileSystemEvent.modify]: an atomic rename over an existing
/// file reports as a delete of the destination on Windows.
StreamSubscription<FileSystemEvent> watchQuakeSummon({
  required File file,
  required void Function() onSummon,
}) {
  return file.parent
      .watch(events: FileSystemEvent.modify | FileSystemEvent.delete)
      .where((event) => event.path == file.path)
      .listen((_) {
        if (!file.existsSync()) return;
        try {
          file.deleteSync();
        } on FileSystemException {
          // Another watcher may have already deleted it — harmless.
        }
        onSummon();
      }, onError: (_) {});
}

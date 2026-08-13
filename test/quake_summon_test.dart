import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/quake_summon.dart';
import 'package:path/path.dart' as p;

void main() {
  test('names the summon file inside the support directory', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'orthanc_quake_summon_name_test',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final expected = File(p.join(tempDir.path, 'quake_summon'));

    final result = quakeSummonFile(supportDir: tempDir);

    expect(result.path, expected.path);
  });

  test('calls onSummon after an external write to the file', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'orthanc_quake_summon_watch_test',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final file = quakeSummonFile(supportDir: tempDir);
    // Seeded directly rather than through requestQuakeSummon(): two renames
    // through the same pid-based temp path from this process, close
    // together, land close enough for macOS FSEvents to coalesce — the same
    // trap settings_watch_test.dart documents for writeSettings().
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('seed');

    var summoned = 0;
    final subscription = watchQuakeSummon(
      file: file,
      onSummon: () => summoned++,
    );
    addTearDown(subscription.cancel);

    requestQuakeSummon(file: file);

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (summoned == 0 && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final expected = 1;
    expect(summoned, expected);
  });

  test(
    'deletes the sentinel once handled, so a stale one self-heals',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'orthanc_quake_summon_delete_test',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final file = quakeSummonFile(supportDir: tempDir);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('seed');

      final subscription = watchQuakeSummon(file: file, onSummon: () {});
      addTearDown(subscription.cancel);

      requestQuakeSummon(file: file);

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (file.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(file.existsSync(), isFalse);
    },
  );
}

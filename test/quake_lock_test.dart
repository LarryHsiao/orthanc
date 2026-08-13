import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/quake_lock.dart';
import 'package:path/path.dart' as p;

// Cross-process exclusion is deliberately not tested here: POSIX file locks
// are per-process, so a second lock attempt from the same process behaves
// differently across platforms for reasons unrelated to correctness — see
// acquireQuakeLock's doc comment.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('orthanc_quake_lock_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('names the lock file inside the support directory', () {
    final expected = File(p.join(tempDir.path, 'quake.lock'));

    final result = quakeLockFile(supportDir: tempDir);

    expect(result.path, expected.path);
  });

  test('acquiring a fresh lock succeeds', () {
    final file = quakeLockFile(supportDir: tempDir);

    final lock = acquireQuakeLock(file: file);

    expect(lock, isNotNull);
    releaseQuakeLock(lock!);
  });

  test('creates the parent directory if it does not exist yet', () {
    final file = File(p.join(tempDir.path, 'nested', 'quake.lock'));

    final lock = acquireQuakeLock(file: file);

    expect(lock, isNotNull);
    expect(file.parent.existsSync(), isTrue);
    releaseQuakeLock(lock!);
  });

  test('releasing the lock allows it to be re-acquired', () {
    final file = quakeLockFile(supportDir: tempDir);
    final first = acquireQuakeLock(file: file);
    releaseQuakeLock(first!);

    final second = acquireQuakeLock(file: file);

    expect(second, isNotNull);
    releaseQuakeLock(second!);
  });
}

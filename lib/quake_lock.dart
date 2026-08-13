import 'dart:io';

import 'package:path/path.dart' as p;

/// The exclusive lock a quake instance holds for as long as it runs.
///
/// Backed by a kernel-held file lock rather than a pid file, so a crashed
/// process leaves no stale state to heal — the lock releases the moment its
/// file descriptor closes, crash included.
File quakeLockFile({required Directory supportDir}) {
  return File(p.join(supportDir.path, 'quake.lock'));
}

/// Claims the quake lock, or returns null if another process already holds
/// it. The caller must keep the returned handle open for as long as it wants
/// to hold the lock — [releaseQuakeLock] (or the process exiting) frees it.
///
/// Cross-process exclusion itself is not exercised by this repo's tests:
/// POSIX file locks are per-process, so a second lock attempt from the same
/// process would pass on some platforms and fail on others for reasons that
/// have nothing to do with correctness. See `quake_lock_test.dart`.
RandomAccessFile? acquireQuakeLock({required File file}) {
  file.parent.createSync(recursive: true);
  final handle = file.openSync(mode: FileMode.append);
  try {
    handle.lockSync(FileLock.exclusive);
    return handle;
  } on FileSystemException {
    handle.closeSync();
    return null;
  }
}

void releaseQuakeLock(RandomAccessFile handle) {
  handle.closeSync();
}

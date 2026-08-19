import 'dart:io';

import 'package:path/path.dart' as p;

/// Where this process's pane handoff endpoint lives — the plain path
/// `Pty.listen`/`Pty.send` (the fork's `pty_listen`/`pty_send`) take as
/// their `endpoint` argument, an `AF_UNIX` socket on POSIX. Named by [pid]
/// alone, so a sender can reach a running instance's endpoint without a
/// separate registry file — any process that knows another's pid already
/// knows where to find it.
File handoffEndpointFile({required Directory supportDir, required int pid}) {
  return File(p.join(supportDir.path, 'handoff-$pid.sock'));
}

final _handoffEndpointName = RegExp(r'^handoff-(\d+)\.sock$');

/// Every `handoff-<pid>.sock` file under [supportDir], paired with the pid
/// parsed from its own name — the one place that naming pattern is read.
/// Shared by [staleHandoffEndpoints] and [liveHandoffEndpoints], which
/// differ only in which half of the split they keep.
Iterable<({File file, int pid})> _handoffEndpoints(Directory supportDir) sync* {
  if (!supportDir.existsSync()) return;

  for (final entity in supportDir.listSync()) {
    if (entity is! File) continue;
    final match = _handoffEndpointName.firstMatch(p.basename(entity.path));
    if (match == null) continue;
    yield (file: entity, pid: int.parse(match.group(1)!));
  }
}

/// Every handoff endpoint under [supportDir] left behind by a process that
/// no longer exists — a crashed instance never gets the chance to close
/// its own listening socket, so its file lingers until something sweeps
/// it. Finds, never deletes; the caller decides what to do with the
/// result.
///
/// [isAlive] is injected rather than baked in as a real OS liveness check,
/// so this stays a pure function of the filesystem plus a predicate — the
/// caller supplies the actual check (POSIX has no liveness probe exposed
/// through `dart:io` as clean as a bare `kill(pid, 0)`; production must
/// pick its own mechanism).
List<File> staleHandoffEndpoints({
  required Directory supportDir,
  required bool Function(int pid) isAlive,
}) {
  return [
    for (final endpoint in _handoffEndpoints(supportDir))
      if (!isAlive(endpoint.pid)) endpoint.file,
  ];
}

/// Every *other* live handoff endpoint under [supportDir] — a running
/// instance's own socket, excluding [ownPid] — the candidates an outgoing
/// pane handoff may be addressed to. Paired with each endpoint's pid,
/// since a sender needs both: the path itself, and the pid to pass through
/// as `Pty.send`'s `targetPid` (meaningful on Windows, where a receiving
/// process must be named explicitly for `DuplicateHandle`).
List<({File file, int pid})> liveHandoffEndpoints({
  required Directory supportDir,
  required int ownPid,
  required bool Function(int pid) isAlive,
}) {
  return [
    for (final endpoint in _handoffEndpoints(supportDir))
      if (endpoint.pid != ownPid && isAlive(endpoint.pid)) endpoint,
  ];
}

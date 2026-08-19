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
  if (!supportDir.existsSync()) return [];

  return supportDir.listSync().whereType<File>().where((file) {
    final match = _handoffEndpointName.firstMatch(p.basename(file.path));
    if (match == null) return false;
    return !isAlive(int.parse(match.group(1)!));
  }).toList();
}

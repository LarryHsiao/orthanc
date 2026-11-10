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

/// Whether a drag that leaves a window's tree should attempt cross-instance
/// handoff at all. Disabled on Windows — [isWindows] is injected rather
/// than read from `Platform.isWindows` directly, so this stays a pure,
/// unit-testable predicate; the caller supplies the real platform check.
bool crossInstanceHandoffSupported({required bool isWindows}) => !isWindows;

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

/// A running instance's handoff endpoint, with the pid that owns it.
typedef HandoffEndpoint = ({File file, int pid});

/// Offers a pane to [endpoints] one at a time, in order, and returns the first
/// that accepts it — or null when none does. A throwing [attempt] counts as a
/// rejection, so one broken endpoint never hides the good ones behind it.
///
/// A pid that merely answers a liveness probe is not proof of an Orthanc: a
/// dead instance's pid can be recycled by an unrelated process while its
/// socket file lingers. Trying each candidate in turn means such a ghost
/// costs one refused offer rather than the whole handoff.
Future<HandoffEndpoint?> firstAcceptingEndpoint(
  List<HandoffEndpoint> endpoints,
  Future<bool> Function(HandoffEndpoint endpoint) attempt,
) async {
  for (final endpoint in endpoints) {
    try {
      if (await attempt(endpoint)) return endpoint;
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// Deletes every endpoint [staleHandoffEndpoints] finds. A file that cannot be
/// deleted (already gone, or not ours to remove) is left; the next launch
/// tries again.
void removeStaleHandoffEndpoints({
  required Directory supportDir,
  required bool Function(int pid) isAlive,
}) {
  for (final file in staleHandoffEndpoints(
    supportDir: supportDir,
    isAlive: isAlive,
  )) {
    try {
      file.deleteSync();
    } on FileSystemException {
      continue;
    }
  }
}

/// Whether [psOutput] — the `comm` column `ps -p <pid> -o comm=` prints — names
/// [executableName]. macOS prints the full path and Linux the bare name; either
/// is compared by its last path segment, exactly, so `orthanc-helper` is not
/// `orthanc`.
bool commandNamesExecutable(String psOutput, String executableName) {
  final command = psOutput.trim();
  return command.isNotEmpty && p.basename(command) == executableName;
}

/// Whether [pid] is a running instance of [executableName], not just any live
/// process. A bare liveness probe is fooled when a dead instance's pid is
/// recycled by an unrelated process; asking `ps` what the pid runs is not.
///
/// When `ps` cannot be run at all the answer is yes: this decides what gets
/// deleted, and a leftover socket costs less than a live instance's endpoint
/// removed.
bool isLiveInstance(int pid, {required String executableName}) {
  if (!Process.killPid(pid, ProcessSignal.sigcont)) return false;
  try {
    final result = Process.runSync('ps', ['-p', '$pid', '-o', 'comm=']);
    return psSaysLive(result.exitCode, result.stdout as String, executableName);
  } on ProcessException {
    return true;
  }
}

/// Reads one `ps -p <pid> -o comm=` run. Exit 0 names the process, so the
/// answer is whether it is [executableName]; exit 1 with nothing printed is
/// how `ps` says there is no such pid. Every other outcome — a denied or
/// failed `ps` — is read as live, for the reason [isLiveInstance] gives.
bool psSaysLive(int exitCode, String stdout, String executableName) {
  if (exitCode == 0) return commandNamesExecutable(stdout, executableName);
  return !(exitCode == 1 && stdout.trim().isEmpty);
}

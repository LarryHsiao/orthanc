import 'dart:io';

import 'package:path/path.dart' as p;

/// Which instance a process is, decided from its command-line arguments.
///
/// `first` alone runs the launch-time update check (see `AppRoot`). `quake`
/// additionally marks the process as the single dedicated drop-down-terminal
/// instance — see `quake_window.dart`.
enum InstanceKind { first, secondary, quake }

/// Marks a spawned instance as not the first one, so it skips the launch-time
/// update check (see `AppRoot`). Passed on the new process's command line and
/// read back by `main()`'s own argument list.
const secondaryInstanceArgument = 'secondary';

/// Marks a spawned instance as the dedicated quake (drop-down terminal)
/// instance. See `quake_window.dart`.
const quakeInstanceArgument = 'quake';

/// Decides which [InstanceKind] a process is from its command-line arguments.
///
/// `quake` wins over `secondary` when both are somehow present — it is the
/// more specific claim.
InstanceKind instanceKind({required List<String> arguments}) {
  if (arguments.contains(quakeInstanceArgument)) return InstanceKind.quake;
  if (arguments.contains(secondaryInstanceArgument)) {
    return InstanceKind.secondary;
  }
  return InstanceKind.first;
}

List<String> _argumentsFor(InstanceKind kind) => switch (kind) {
  InstanceKind.first => const [],
  InstanceKind.secondary => const [secondaryInstanceArgument],
  InstanceKind.quake => const [quakeInstanceArgument],
};

/// The command that starts another instance of this app: its executable and
/// the arguments to hand it.
///
/// Each window is its own process rather than a second `FlutterEngine` in this
/// one, so a window's sessions live and die with an OS process — nothing here
/// must track their lifetime by hand. The two platforms need different verbs:
///
/// * macOS refuses a second instance of an already-running bundle unless asked
///   through `open -n`, and wants the `.app` rather than the Mach-O buried
///   inside it — three directories above [resolvedExecutable], which is always
///   `<bundle>.app/Contents/MacOS/<name>`. `open` is named by its full path
///   because a double-clicked app inherits no useful `PATH`, and a detached
///   spawn whose exec fails reports nothing back to raise.
/// * Windows has no such rule; the executable starts directly.
///
/// A pure decision with no I/O, in the same shape as `shellCommand()` — the
/// caller spawns.
({String executable, List<String> arguments}) newInstanceCommand({
  required bool isMacOS,
  required String resolvedExecutable,
  InstanceKind kind = InstanceKind.secondary,
}) {
  final args = _argumentsFor(kind);
  if (!isMacOS) {
    return (executable: resolvedExecutable, arguments: args);
  }
  final bundle = p.dirname(p.dirname(p.dirname(resolvedExecutable)));
  return (
    executable: '/usr/bin/open',
    arguments: ['-n', '-a', bundle, if (args.isNotEmpty) '--args', ...args],
  );
}

/// Starts another instance of this app, detached, so it outlives the one that
/// asked for it. Shared by the macOS menu item and the Windows hotkey.
///
/// A failed spawn is swallowed by design, as the launch-time update check is:
/// there is nothing to raise it to, and the user can simply ask again.
Future<void> startNewInstance({
  InstanceKind kind = InstanceKind.secondary,
}) async {
  final command = newInstanceCommand(
    isMacOS: Platform.isMacOS,
    resolvedExecutable: Platform.resolvedExecutable,
    kind: kind,
  );
  try {
    await Process.start(
      command.executable,
      command.arguments,
      mode: ProcessStartMode.detached,
    );
  } on ProcessException {
    // See above: nothing to report it to.
  }
}

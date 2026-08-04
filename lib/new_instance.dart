import 'dart:io';

import 'package:path/path.dart' as p;

/// Marks a spawned instance as not the first one, so it skips the launch-time
/// update check (see `AppRoot`). Passed on the new process's command line and
/// read back by `main()`'s own argument list.
const secondaryInstanceArgument = 'secondary';

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
}) {
  if (!isMacOS) {
    return (
      executable: resolvedExecutable,
      arguments: const [secondaryInstanceArgument],
    );
  }
  final bundle = p.dirname(p.dirname(p.dirname(resolvedExecutable)));
  return (
    executable: '/usr/bin/open',
    arguments: ['-n', '-a', bundle, '--args', secondaryInstanceArgument],
  );
}

/// Starts another instance of this app, detached, so it outlives the one that
/// asked for it. Shared by the macOS menu item and the Windows hotkey.
///
/// A failed spawn is swallowed by design, as the launch-time update check is:
/// there is nothing to raise it to, and the user can simply ask again.
Future<void> startNewInstance() async {
  final command = newInstanceCommand(
    isMacOS: Platform.isMacOS,
    resolvedExecutable: Platform.resolvedExecutable,
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

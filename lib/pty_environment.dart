/// The environment handed to the spawned process, or null to add nothing.
///
/// flutter_pty does not inherit the parent environment — it builds the child's
/// from scratch, hardcoding TERM and LANG and copying only a fixed allowlist
/// (LOGNAME, USER, DISPLAY, LC_TYPE, HOME, PATH). That set is POSIX-shaped, and
/// on Windows it strips SystemRoot, without which a spawned executable loads no
/// system DLLs and dies before printing anything — `claude` was found, launched,
/// and gone, with an empty stderr to show for it. Forward the whole environment
/// there, as a terminal emulator is expected to.
///
/// TERM and LANG are withheld from that forwarding. flutter_pty hardcodes both
/// and applies the caller's map *last*, so passing them through would let
/// whatever shell happened to launch the app override the emulator's own
/// choice — a Git Bash parent could impose `TERM=cygwin`, or a `LANG` that is
/// not UTF-8, which flutter_pty's own source warns produces byte sequences
/// tools like `vi` cannot render. A terminal emulator names its own terminal.
///
/// Elsewhere the allowlist is right, and only COLORTERM is missing from it: the
/// host may be truecolor-capable, but a spawned CLI that cannot read COLORTERM
/// may settle for a more limited color mode.
Map<String, String>? ptyEnvironment({
  required bool isWindows,
  required Map<String, String> environment,
}) {
  if (isWindows) {
    return Map.of(environment)
      ..remove('TERM')
      ..remove('LANG');
  }

  final colorterm = environment['COLORTERM'];
  return colorterm != null ? {'COLORTERM': colorterm} : null;
}

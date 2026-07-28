/// The environment overrides to hand the spawned process.
///
/// flutter_pty does not inherit the parent environment — it builds the child's
/// from scratch, hardcoding TERM and LANG and copying only a fixed allowlist
/// (LOGNAME, USER, DISPLAY, LC_TYPE, HOME, PATH). That set is POSIX-shaped, and
/// on Windows it strips SystemRoot, without which a spawned executable loads no
/// system DLLs and dies before printing anything — `claude` was found, launched,
/// and gone, with an empty stderr to show for it. Forward the whole environment
/// there, as a terminal emulator is expected to.
///
/// NO_COLOR is withheld too, and that one corrects an asymmetry rather than
/// setting a policy: flutter_pty copies only LOGNAME/USER/DISPLAY/LC_TYPE/
/// HOME/PATH, so NO_COLOR has never reached a macOS pane at all — only the
/// Windows branch's wholesale forwarding let it through. It describes whether
/// the *launcher's* output sink can render color, which says nothing about a
/// fresh xterm-256color pane that plainly can. This app is a Claude Code
/// companion and Claude Code sets NO_COLOR for its subprocesses, so being
/// launched from one is an ordinary path, not an exotic one — and every pane
/// under such a launch came up colorless. A program inside a pane that truly
/// wants no color can still set it for itself.
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
/// Names never handed to a pane on Windows, held lowercase because each
/// candidate is folded to that before the comparison. Windows treats
/// environment variable names case-insensitively, so a parent exporting `Term`
/// or `No_Color` names the same variable the child would read as `TERM` or
/// `NO_COLOR` — an exact-match removal would let it straight through.
const _withheldOnWindows = {'term', 'lang', 'no_color'};

/// FORCE_HYPERLINK is always injected, on every platform. A hyperlink-aware
/// CLI (Claude Code included) only emits OSC 8 once it recognizes the
/// terminal as capable — typically by TERM_PROGRAM matching a known emulator
/// (iTerm.app, WezTerm, vscode, ghostty) or VTE_VERSION being set — checks
/// this pane's TERM=xterm-256color will never satisfy, since Orthanc is none
/// of those. FORCE_HYPERLINK is the escape hatch such CLIs already honor to
/// skip that detection.
Map<String, String> ptyEnvironment({
  required bool isWindows,
  required Map<String, String> environment,
}) {
  final base = isWindows
      ? {
          for (final entry in environment.entries)
            if (!_withheldOnWindows.contains(entry.key.toLowerCase()))
              entry.key: entry.value,
        }
      : {'COLORTERM': ?environment['COLORTERM']};
  return {...base, 'FORCE_HYPERLINK': '1'};
}

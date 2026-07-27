import 'dart:io';

import 'home_directory.dart';

/// A shell this app knows how to add a title-on-prompt hook to.
enum ShellKind { bash, zsh }

/// [executable]'s final path segment, lowercased and stripped of a Windows
/// `.exe` extension — so `C:\Program Files\Git\bin\bash.exe` and `/bin/bash`
/// name the same shell.
String _baseName(String executable) {
  final segment = executable.split(RegExp(r'[\\/]')).last.toLowerCase();
  return segment.endsWith('.exe')
      ? segment.substring(0, segment.length - 4)
      : segment;
}

/// Which [ShellKind] [executable] is, or null for a shell this app leaves
/// alone — its pane then just shows whatever title it last happened to set,
/// as before this feature existed.
ShellKind? shellKind(String executable) {
  switch (_baseName(executable)) {
    case 'bash':
      return ShellKind.bash;
    case 'zsh':
      return ShellKind.zsh;
    default:
      return null;
  }
}

/// The OSC 1 + OSC 2 sequence, in shell syntax, that announces the shell's
/// own working directory as both the pane's current activity (OSC 2) and,
/// deliberately, its name (OSC 1) — this only ever fires from an idle
/// prompt redraw, when no foreground child process could have set a name of
/// its own, so resetting OSC 1 here can only clear a stale name a since-
/// exited program left behind. That reset is what makes `paneTitle()`'s
/// `name == activity` collapse apply once idle, instead of a finished
/// program's name lingering as a permanent prefix.
const _titleHookFunction = r'''
__orthanc_title_hook() {
  printf '\033]1;%s\033\\\033]2;%s\033\\' "$PWD" "$PWD"
}
''';

/// The rc file bash should read instead of `~/.bashrc`: sources the user's
/// own rc file first (if [userBashrc] is given), then adds the title hook so
/// it fires on every prompt redraw, without discarding whatever the user's
/// own `PROMPT_COMMAND` already did.
String bashPromptHookScript({required String? userBashrc}) {
  final source = userBashrc == null
      ? ''
      : '[ -f "$userBashrc" ] && source "$userBashrc"\n';
  return '$source$_titleHookFunction'
      'PROMPT_COMMAND="__orthanc_title_hook\${PROMPT_COMMAND:+; \$PROMPT_COMMAND}"\n';
}

/// The `.zshrc` a temporary `ZDOTDIR` should hold: sources the user's own
/// `.zshrc` first (if [userZshrc] is given), then adds the title hook to
/// `precmd_functions` so it fires on every prompt redraw alongside whatever
/// hooks the user's own rc file already installed.
String zshPromptHookScript({required String? userZshrc}) {
  final source = userZshrc == null
      ? ''
      : '[ -f "$userZshrc" ] && source "$userZshrc"\n';
  return '$source$_titleHookFunction'
      'precmd_functions+=(__orthanc_title_hook)\n';
}

/// The `.zshenv` a temporary `ZDOTDIR` should hold: sources the user's own
/// `.zshenv` (if [userZshenv] is given). zsh reads `.zshenv` for every
/// invocation, interactive or not — commonly carrying `PATH`/env setup —
/// and skips it entirely once `ZDOTDIR` points elsewhere unless something
/// puts one there.
String zshEnvHookScript({required String? userZshenv}) {
  if (userZshenv == null) return '';
  return '[ -f "$userZshenv" ] && source "$userZshenv"\n';
}

/// The `.zprofile` a temporary `ZDOTDIR` should hold: sources the user's own
/// `.zprofile` (if [userZshProfile] is given). zsh reads `.zprofile` only for
/// login shells — which is why [shellPromptHook] launches zsh with `-l` —
/// and skips it entirely once `ZDOTDIR` points elsewhere unless something
/// puts one there. This is where Homebrew's installer places its PATH setup
/// (`eval "$(brew shellenv)"`), so a released, double-clicked build — which
/// inherits no shell's PATH to begin with — would never see `/opt/homebrew/bin`
/// without this.
String zshProfileHookScript({required String? userZshProfile}) {
  if (userZshProfile == null) return '';
  return '[ -f "$userZshProfile" ] && source "$userZshProfile"\n';
}

/// The `cmd.exe` arguments that make it announce its own path as the pane's
/// current activity (and, deliberately, its name — see [_titleHookFunction]
/// for why resetting both here is safe) on every prompt: `$P` (path) and
/// `$G$S` (`> `, cmd's own default prompt tail) are both re-evaluated by
/// cmd.exe on every prompt redraw, so — unlike bash/zsh — no rc-file
/// injection is needed.
List<String> cmdPromptHookArguments() {
  return ['/K', r'prompt $E]1;$P$E\$E]2;$P$E\$P$G$S'];
}

/// What to hand `Pty.start`, on top of what [executable] already needs, so
/// the pane announces its own pwd once idle instead of showing a stale title
/// a finished program left behind.
class ShellLaunch {
  const ShellLaunch({required this.arguments, required this.environment});

  static const none = ShellLaunch(arguments: [], environment: {});

  final List<String> arguments;
  final Map<String, String> environment;
}

/// Builds [executable]'s [ShellLaunch], writing whatever temp rc file its
/// shell needs. Returns [ShellLaunch.none] for a shell this app doesn't know
/// how to hook — see [shellKind]. `cmd.exe` is hooked by name rather than by
/// [ShellKind]: its hook is launch arguments, not an rc file, and only
/// cmd.exe understands the `$P`/`$G$S` prompt syntax they carry — handing
/// them to a Windows shell configured to something else (Git Bash's
/// `bash.exe`, say) makes that shell fail to start.
ShellLaunch shellPromptHook({
  required bool isWindows,
  required String executable,
  required Map<String, String> environment,
}) {
  switch (shellKind(executable)) {
    case ShellKind.bash:
      return _installBashHook(isWindows: isWindows, environment: environment);
    case ShellKind.zsh:
      return _installZshHook(isWindows: isWindows, environment: environment);
    case null:
      if (isWindows && _baseName(executable) == 'cmd') {
        return ShellLaunch(
          arguments: cmdPromptHookArguments(),
          environment: const {},
        );
      }
      return ShellLaunch.none;
  }
}

// Resolved through homeDirectory(), not environment['HOME'] directly: Windows
// never sets HOME of its own, so a double-clicked or Start-menu launch has
// none, and reading it alone silently drops the source line — the user's rc
// file then never loads, while /etc/bash.bashrc still does, leaving a pane
// that looks almost right. Only a launch descended from a shell that exports
// HOME behaved correctly, which is why this hid for so long.
ShellLaunch _installBashHook({
  required bool isWindows,
  required Map<String, String> environment,
}) {
  final home = homeDirectory(isWindows: isWindows, environment: environment);
  final userBashrc = home == null ? null : '$home/.bashrc';
  final dir = Directory.systemTemp.createTempSync('orthanc-bash-');
  File(
    '${dir.path}/bashrc',
  ).writeAsStringSync(bashPromptHookScript(userBashrc: userBashrc));
  return ShellLaunch(
    arguments: ['--rcfile', '${dir.path}/bashrc'],
    environment: const {},
  );
}

// Same home resolution as [_installBashHook], for the same reason. On macOS,
// where zsh actually lives, homeDirectory() returns HOME verbatim, so nothing
// changes there; it only closes the identical hole on Windows.
ShellLaunch _installZshHook({
  required bool isWindows,
  required Map<String, String> environment,
}) {
  final originalZdotdir =
      environment['ZDOTDIR'] ??
      homeDirectory(isWindows: isWindows, environment: environment);
  final userZshrc = originalZdotdir == null ? null : '$originalZdotdir/.zshrc';
  final userZshenv = originalZdotdir == null
      ? null
      : '$originalZdotdir/.zshenv';
  final userZshProfile = originalZdotdir == null
      ? null
      : '$originalZdotdir/.zprofile';
  final dir = Directory.systemTemp.createTempSync('orthanc-zsh-');
  File(
    '${dir.path}/.zshenv',
  ).writeAsStringSync(zshEnvHookScript(userZshenv: userZshenv));
  File(
    '${dir.path}/.zprofile',
  ).writeAsStringSync(zshProfileHookScript(userZshProfile: userZshProfile));
  File(
    '${dir.path}/.zshrc',
  ).writeAsStringSync(zshPromptHookScript(userZshrc: userZshrc));
  return ShellLaunch(
    arguments: const ['-l'],
    environment: {'ZDOTDIR': dir.path},
  );
}

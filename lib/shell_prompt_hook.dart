import 'dart:io';

/// A shell this app knows how to add a title-on-prompt hook to.
enum ShellKind { bash, zsh }

/// Which [ShellKind] [executable] is, or null for a shell this app leaves
/// alone — its pane then just shows whatever title it last happened to set,
/// as before this feature existed.
ShellKind? shellKind(String executable) {
  final name = executable.split('/').last;
  if (name == 'bash') return ShellKind.bash;
  if (name == 'zsh') return ShellKind.zsh;
  return null;
}

/// The OSC 2 sequence, in shell syntax, that announces the shell's own
/// working directory as the pane's current activity. OSC 2 specifically —
/// never OSC 0 — so it never touches the session name a running program set
/// on OSC 1.
const _titleHookFunction = r'''
__orthanc_title_hook() {
  printf '\033]2;%s\033\\' "$PWD"
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

/// The `cmd.exe` arguments that make it announce its own path as the pane's
/// current activity on every prompt: `$P` (path) and `$G$S` (`> `, cmd's own
/// default prompt tail) are both re-evaluated by cmd.exe on every prompt
/// redraw, so — unlike bash/zsh — no rc-file injection is needed.
List<String> cmdPromptHookArguments() {
  return ['/K', r'prompt $E]2;$P$E\$P$G$S'];
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
/// how to hook — see [shellKind].
ShellLaunch shellPromptHook({
  required bool isWindows,
  required String executable,
  required Map<String, String> environment,
}) {
  if (isWindows) {
    return ShellLaunch(
      arguments: cmdPromptHookArguments(),
      environment: const {},
    );
  }
  switch (shellKind(executable)) {
    case ShellKind.bash:
      return _installBashHook(environment: environment);
    case ShellKind.zsh:
      return _installZshHook(environment: environment);
    case null:
      return ShellLaunch.none;
  }
}

ShellLaunch _installBashHook({required Map<String, String> environment}) {
  final home = environment['HOME'];
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

ShellLaunch _installZshHook({required Map<String, String> environment}) {
  final originalZdotdir = environment['ZDOTDIR'] ?? environment['HOME'];
  final userZshrc = originalZdotdir == null ? null : '$originalZdotdir/.zshrc';
  final dir = Directory.systemTemp.createTempSync('orthanc-zsh-');
  File(
    '${dir.path}/.zshrc',
  ).writeAsStringSync(zshPromptHookScript(userZshrc: userZshrc));
  return ShellLaunch(arguments: const [], environment: {'ZDOTDIR': dir.path});
}

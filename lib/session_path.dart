import 'pane_title.dart';

/// The working directory a pane's shell last announced, or null when it has
/// announced none — an unhooked shell (PowerShell), or no prompt drawn yet.
/// [sessionName] is a [Session.name] value; [looksLikePath] is the same test
/// [Session.terminal]'s `onIconChange` already leans on to tell a shell's
/// directory announcement apart from a running program's own OSC title.
String? sessionPath(String sessionName) {
  return looksLikePath(sessionName) ? sessionName : null;
}

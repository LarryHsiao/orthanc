import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

import 'settings.dart';
import 'terminal_color_schemes.dart';
import 'terminal_font_families.dart';

/// Static sample lines written into every preview terminal — a prompt, a
/// colored directory listing exercising the palette's accents, an error
/// line, and a git-branch-style accent row.
const _sampleContent =
    'orthanc:~ \$ ls -la\r\n'
    '\x1B[34mDocuments\x1B[0m  \x1B[32mDownloads\x1B[0m  '
    '\x1B[33mProjects\x1B[0m  notes.txt\r\n'
    '\x1B[31mzsh: command not found: fzf\x1B[0m\r\n'
    '\x1B[36m‣ main\x1B[0m \x1B[35m✗\x1B[0m';

/// A [Terminal] pre-loaded with [_sampleContent], for a non-interactive
/// preview. No PTY is attached — nothing is spawned, nothing can be typed
/// into it.
Terminal buildPreviewTerminal() {
  final terminal = Terminal(maxLines: 100);
  terminal.write(_sampleContent);
  return terminal;
}

/// A small, read-only terminal viewport rendering [scheme]/[fontFamily]/
/// [fontSize] against [buildPreviewTerminal]'s sample content, so a pending
/// pick can be judged before it's saved.
class TerminalPreview extends StatelessWidget {
  const TerminalPreview({
    super.key,
    required this.scheme,
    this.fontFamily = defaultTerminalFontFamily,
    this.fontSize = defaultTerminalFontSize,
  });

  final TerminalColorScheme scheme;
  final String fontFamily;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: TerminalView(
        buildPreviewTerminal(),
        theme: terminalThemeFor(scheme),
        readOnly: true,
        textStyle: TerminalStyle(fontFamily: fontFamily, fontSize: fontSize),
      ),
    );
  }
}

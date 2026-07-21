import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'pane_bar.dart';
import 'session.dart';

/// One pane: its bar, and the terminal beneath.
///
/// The terminal is handed a session rather than spawning one — moving a pane
/// within the layout must not restart its process.
class PaneView extends StatelessWidget {
  const PaneView({
    super.key,
    required this.session,
    required this.focused,
    required this.onFocus,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onFocus(),
      child: Column(
        children: [
          PaneBar(session: session, focused: focused),
          Expanded(child: TerminalView(session.terminal, autofocus: focused)),
        ],
      ),
    );
  }
}

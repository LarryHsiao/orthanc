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
    required this.onKeyEvent,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;
  final FocusOnKeyEventCallback onKeyEvent;

  @override
  Widget build(BuildContext context) {
    // Listener sees every pointer down regardless of the gesture arena; a
    // GestureDetector here would compete with xterm's own tap recognizer and
    // routinely lose it on a brisk click.
    return Listener(
      onPointerDown: (_) => onFocus(),
      child: Column(
        children: [
          PaneBar(session: session, focused: focused),
          Expanded(
            child: TerminalView(
              session.terminal,
              focusNode: session.focusNode,
              onKeyEvent: onKeyEvent,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'pane_bar.dart';
import 'session.dart';

/// One pane: its bar, and the terminal beneath — unless [shrunk], in which
/// case only the bar renders, at its own fixed height, and the terminal is
/// skipped entirely. A pane's [Session] outlives this widget either way.
class PaneView extends StatelessWidget {
  const PaneView({
    super.key,
    required this.session,
    required this.focused,
    required this.onFocus,
    required this.onKeyEvent,
    required this.canCollapse,
    required this.collapsed,
    required this.shrunk,
    required this.onToggleCollapse,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;
  final FocusOnKeyEventCallback onKeyEvent;
  final bool canCollapse;
  final bool collapsed;
  final bool shrunk;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    // Listener sees every pointer down regardless of the gesture arena; a
    // GestureDetector here would compete with xterm's own tap recognizer and
    // routinely lose it on a brisk click.
    return Listener(
      onPointerDown: (_) => onFocus(),
      child: Column(
        children: [
          GestureDetector(
            onTap: canCollapse ? onToggleCollapse : null,
            child: PaneBar(
              session: session,
              focused: focused,
              canCollapse: canCollapse,
              collapsed: collapsed,
            ),
          ),
          if (!shrunk)
            Expanded(
              // xterm's RenderTerminal never clips its own paint, so a scroll
              // can draw rows past its box and into PaneBar above it. Clip
              // explicitly rather than rely on that render object doing it.
              child: ClipRect(
                child: TerminalView(
                  session.terminal,
                  focusNode: session.focusNode,
                  onKeyEvent: onKeyEvent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

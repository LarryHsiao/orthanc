import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import 'hyperlink.dart';
import 'pane_bar.dart';
import 'session.dart';
import 'terminal_font_families.dart';

/// One pane: its bar, and the terminal beneath — unless [collapsed], in
/// which case only the bar renders, at its own fixed height, and the
/// terminal is skipped entirely. A pane's [Session] outlives this widget
/// either way.
class PaneView extends StatefulWidget {
  const PaneView({
    super.key,
    required this.session,
    required this.focused,
    required this.onFocus,
    required this.onKeyEvent,
    required this.canCollapse,
    required this.collapsed,
    required this.theme,
    required this.fontFamily,
    required this.fontSize,
    required this.onToggleCollapse,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;
  final FocusOnKeyEventCallback onKeyEvent;
  final bool canCollapse;
  final bool collapsed;
  final TerminalTheme theme;
  final String fontFamily;
  final double fontSize;
  final VoidCallback onToggleCollapse;

  @override
  State<PaneView> createState() => _PaneViewState();
}

class _PaneViewState extends State<PaneView> {
  final _terminalKey = GlobalKey<TerminalViewState>();
  MouseCursor _cursor = SystemMouseCursors.text;

  @override
  Widget build(BuildContext context) {
    // Listener sees every pointer down regardless of the gesture arena; a
    // GestureDetector here would compete with xterm's own tap recognizer and
    // routinely lose it on a brisk click.
    return Listener(
      onPointerDown: (_) => widget.onFocus(),
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.canCollapse ? widget.onToggleCollapse : null,
            child: PaneBar(
              session: widget.session,
              focused: widget.focused,
              canCollapse: widget.canCollapse,
              collapsed: widget.collapsed,
            ),
          ),
          if (!widget.collapsed)
            Expanded(
              // xterm's RenderTerminal never clips its own paint, so a scroll
              // can draw rows past its box and into PaneBar above it. Clip
              // explicitly rather than rely on that render object doing it.
              child: ClipRect(
                child: MouseRegion(
                  onHover: _onHover,
                  onExit: (_) => _setCursor(SystemMouseCursors.text),
                  child: TerminalView(
                    key: _terminalKey,
                    widget.session.terminal,
                    focusNode: widget.session.focusNode,
                    onKeyEvent: widget.onKeyEvent,
                    onTapUp: _onTapUp,
                    mouseCursor: _cursor,
                    theme: widget.theme,
                    // See terminalFontFamilyFallback's doc comment for why
                    // this list is shaped and ordered the way it is.
                    textStyle: TerminalStyle(
                      fontFamily: widget.fontFamily,
                      fontSize: widget.fontSize,
                      fontFamilyFallback: terminalFontFamilyFallback,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onHover(PointerHoverEvent event) {
    final state = _terminalKey.currentState;
    if (state == null) return;
    final offset = state.renderTerminal.getCellOffset(event.localPosition);
    final launchable =
        _isLinkModifierHeld() && _launchableHyperlinkAt(offset) != null;
    _setCursor(launchable ? SystemMouseCursors.click : SystemMouseCursors.text);
  }

  void _onTapUp(TapUpDetails details, CellOffset offset) {
    if (!_isLinkModifierHeld()) return;
    final uri = _launchableHyperlinkAt(offset);
    if (uri == null) return;
    launchUrl(Uri.parse(uri));
  }

  void _setCursor(MouseCursor cursor) {
    if (cursor == _cursor) return;
    setState(() => _cursor = cursor);
  }

  bool _isLinkModifierHeld() {
    final keys = HardwareKeyboard.instance;
    return isHyperlinkModifierPressed(
      isWindows: Platform.isWindows,
      isControlPressed: keys.isControlPressed,
      isMetaPressed: keys.isMetaPressed,
    );
  }

  String? _launchableHyperlinkAt(CellOffset offset) {
    final uri = widget.session.terminal.hyperlinkAt(offset);
    return isLaunchableHyperlink(uri) ? uri : null;
  }
}

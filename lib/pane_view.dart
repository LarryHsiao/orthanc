import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import 'hyperlink.dart';
import 'pane_bar.dart';
import 'session.dart';

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
    required this.onToggleCollapse,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;
  final FocusOnKeyEventCallback onKeyEvent;
  final bool canCollapse;
  final bool collapsed;
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
                    // xterm's built-in fallback list is Linux/Android-flavored
                    // and omits Hack Nerd Font Mono, so the Private-Use-Area
                    // glyphs shell tools (lsd, oh-my-posh, ...) use for icons
                    // render as tofu unless named explicitly here — a no-op
                    // fallback entry on a machine that lacks it.
                    //
                    // Apple Color Emoji / Segoe UI Emoji are deliberately absent:
                    // both claim dingbat codepoints that also have a plain-text
                    // glyph (Claude Code's spinner frames — ✢ ✳ ✻ ✽ — and its
                    // ⏺ paragraph bullet included), and being first in the list
                    // would win the match and render them in color instead of
                    // the monochrome glyph a native terminal shows.
                    //
                    // The trailing entries below are copied verbatim from the
                    // fork's private _kDefaultFontFamilyFallback (unexported,
                    // so not importable) — lib/src/ui/terminal_text_style.dart
                    // at the pinned pubspec.yaml ref. Re-sync if that list
                    // changes upstream.
                    textStyle: const TerminalStyle(
                      fontFamilyFallback: [
                        'Hack Nerd Font Mono',
                        'Menlo',
                        'Monaco',
                        'Consolas',
                        'Liberation Mono',
                        'Courier New',
                        'Noto Sans Mono CJK SC',
                        'Noto Sans Mono CJK TC',
                        'Noto Sans Mono CJK KR',
                        'Noto Sans Mono CJK JP',
                        'Noto Sans Mono CJK HK',
                        'Noto Color Emoji',
                        'Noto Sans Symbols',
                        'monospace',
                        'sans-serif',
                      ],
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

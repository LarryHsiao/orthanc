import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'pane_bar.dart';
import 'session.dart';

/// One pane: its bar, and the terminal beneath — unless [collapsed], in
/// which case only the bar renders, at its own fixed height, and the
/// terminal is skipped entirely. A pane's [Session] outlives this widget
/// either way.
class PaneView extends StatelessWidget {
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
          if (!collapsed)
            Expanded(
              // xterm's RenderTerminal never clips its own paint, so a scroll
              // can draw rows past its box and into PaneBar above it. Clip
              // explicitly rather than rely on that render object doing it.
              child: ClipRect(
                child: TerminalView(
                  session.terminal,
                  focusNode: session.focusNode,
                  onKeyEvent: onKeyEvent,
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
        ],
      ),
    );
  }
}

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
///
/// When [focused], an accent border is painted over the pane's bounds — see
/// [focusBorderKey] for why it is an overlay rather than a decoration.
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

  /// The focus border is painted *over* the pane, never around it. xterm
  /// sizes its cell grid to the box it is handed, so a border that consumed
  /// layout would reflow the pty — and resize every running program — each
  /// time focus moved between panes.
  static const focusBorderKey = Key('pane-focus-border');

  static const focusBorderWidth = 2.0;

  /// How far the focus accent travels from the terminal's background toward
  /// the palette's blue. The raw blue out-shouts the text it frames; below
  /// about a half the mark sinks back toward the eye's floor, and a dark
  /// palette's blue reaches its own background first.
  static const focusAccentStrength = 0.6;

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
      // The body took whatever constraints its parent gave before the Stack
      // stood between them; expand passes those through unchanged, rather
      // than loosening them and leaving the Column to shrink-wrap.
      child: Stack(
        fit: StackFit.expand,
        children: [_paneBody(), if (widget.focused) _focusBorder()],
      ),
    );
  }

  Widget _paneBody() {
    return Column(
      children: [
        GestureDetector(
          onTap: widget.canCollapse ? widget.onToggleCollapse : null,
          child: PaneBar(
            session: widget.session,
            focused: widget.focused,
            accent: _accent,
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
                  controller: widget.session.terminalController,
                  focusNode: widget.session.focusNode,
                  onKeyEvent: widget.onKeyEvent,
                  onTapUp: _onTapUp,
                  onSecondaryTapUp: _onSecondaryTapUp,
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
    );
  }

  Widget _focusBorder() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          key: PaneView.focusBorderKey,
          decoration: BoxDecoration(
            border: Border.all(
              color: _accent,
              width: PaneView.focusBorderWidth,
            ),
          ),
        ),
      ),
    );
  }

  /// The focus colour. Drawn from the terminal palette rather than the app's
  /// [ColorScheme], which is Flutter's stock light default and bears no
  /// relation to the terminal beneath it. The cursor colour would be the
  /// obvious pick, but every scheme deliberately shares one translucent grey
  /// there (see terminal_color_schemes.dart) — blue is the brightest field
  /// that actually varies with the user's choice.
  ///
  /// Blended back toward the palette's own background at
  /// [PaneView.focusAccentStrength], so the mark sits in the scheme rather
  /// than on top of it. Blended rather than made translucent: the accent
  /// paints over the terminal at the border and over nothing at the bar, so
  /// an alpha would composite differently in the two places.
  Color get _accent => Color.lerp(
    widget.theme.background,
    widget.theme.blue,
    PaneView.focusAccentStrength,
  )!;

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

  /// Copy/Paste independent of the keyboard: a gesture, not a shortcut, so
  /// it needs no shell convention and no cooperation from xterm's own
  /// shortcut manager or IME composing state.
  Future<void> _onSecondaryTapUp(
    TapUpDetails details,
    CellOffset offset,
  ) async {
    widget.onFocus();
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      details.globalPosition & Size.zero,
      Offset.zero & overlay.size,
    );
    final action = await showMenu<_ClipboardMenuAction>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: _ClipboardMenuAction.copy,
          enabled: widget.session.terminalController.selection != null,
          child: const Text('Copy'),
        ),
        const PopupMenuItem(
          value: _ClipboardMenuAction.paste,
          child: Text('Paste'),
        ),
      ],
    );
    switch (action) {
      case _ClipboardMenuAction.copy:
        _copySelection();
      case _ClipboardMenuAction.paste:
        await _pasteFromClipboard();
      case null:
        break;
    }
  }

  // Selection survives a copy — matching xterm's own CopySelectionTextIntent
  // handler, which never clears it either.
  void _copySelection() {
    final selection = widget.session.terminalController.selection;
    if (selection == null) return;
    final text = widget.session.terminal.buffer.getText(selection);
    Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    widget.session.terminal.paste(text);
    widget.session.terminalController.clearSelection();
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

enum _ClipboardMenuAction { copy, paste }

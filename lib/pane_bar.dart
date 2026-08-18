import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pane_title.dart';
import 'session.dart';

/// The thin strip naming a pane.
///
/// Carries a title, and — when [canCollapse] is true — a small collapse
/// affordance a tap on the bar (wired by the caller, not here) toggles.
/// Right-click starts renaming the pane directly; the resulting name lives
/// on [Session.manualName], set only from here, never by the running
/// program. See docs/superpowers/specs/2026-07-23-orthanc-pane-rename-design.md.
///
/// When [focused], the bar fills with [accent] rather than a surface tone.
/// A collapsed pane is nothing but its bar, so this fill is the only mark
/// of focus such a pane can carry — PaneView's border has no body to
/// enclose there. The same fill, in [attentionAccent], marks a pane that
/// finished unwatched — see [Session.needsAttention] — for the same reason:
/// it reads the same whether the pane is expanded or collapsed to its bar
/// alone. Focus always wins where both could apply.
class PaneBar extends StatefulWidget {
  const PaneBar({
    super.key,
    required this.session,
    required this.focused,
    required this.accent,
    required this.attentionAccent,
    required this.canCollapse,
    required this.collapsed,
    required this.canDrag,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  static const height = 22.0;

  static const gripKey = Key('pane-drag-grip');

  final Session session;
  final bool focused;

  /// The focus colour, drawn from the terminal palette the user chose, so
  /// the mark moves with the scheme instead of standing apart from it.
  final Color accent;

  /// The colour for a pane that finished a burst of activity while
  /// unfocused — see [Session.needsAttention]. Loses to [accent] whenever
  /// both could apply; see the fill order in [build].
  final Color attentionAccent;
  final bool canCollapse;
  final bool collapsed;

  final bool canDrag;

  /// Fired once, when a drag on the grip begins.
  final void Function(String id) onDragStart;

  /// Fired on every pointer move during a drag, with the pointer's
  /// current *global* position — the caller (ultimately WorkspaceView)
  /// is what knows how to turn that into a pane underneath it.
  final void Function(String id, Offset globalPosition) onDragUpdate;

  /// Fired once, when the drag ends — by release or cancellation alike.
  final void Function(String id) onDragEnd;

  @override
  State<PaneBar> createState() => _PaneBarState();
}

class _PaneBarState extends State<PaneBar> {
  bool _editing = false;
  final _controller = TextEditingController();
  final _fieldFocusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapUp: (_) => _startEditing(),
      // The fill — and so the ink that must contrast against it — depends on
      // needsAttention, so the whole bar (title row included) has to live
      // inside this builder rather than being hoisted out as a static
      // child. The cost is a title-row rebuild on every attention-flag
      // change; the alternative is a title that goes illegible against its
      // own bar.
      child: ValueListenableBuilder(
        valueListenable: widget.session.needsAttention,
        builder: (context, needsAttention, child) {
          // Marks a pane that finished a burst of activity while unfocused
          // — see Session.needsAttention. Focus always wins: gaining focus
          // clears the flag (Session._onFocusChanged), but the fill order
          // does not lean on that alone — a pane cannot show both at once.
          final fill = widget.focused
              ? widget.accent
              : needsAttention
              ? widget.attentionAccent
              : scheme.surfaceContainer;
          final emphasized = widget.focused || needsAttention;
          final ink = emphasized ? _inkOn(fill) : scheme.onSurface;
          return Container(
            height: PaneBar.height,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(color: fill),
            child: Row(
              children: [
                if (widget.canDrag) _grip(scheme),
                Expanded(child: _editing ? _editField(ink) : _title(ink)),
                if (widget.canCollapse)
                  _collapseIcon(emphasized ? ink : scheme.onSurfaceVariant),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Black or white, whichever reads on [fill]. The palettes on offer run
  /// from Solarized's deep blue to Dracula's pale violet, so one fixed ink
  /// would be illegible at one end or the other.
  Color _inkOn(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
      ? Colors.white
      : Colors.black;

  Widget _grip(ColorScheme scheme) {
    return GestureDetector(
      key: PaneBar.gripKey,
      onPanStart: (_) => widget.onDragStart(widget.session.id),
      onPanUpdate: (details) =>
          widget.onDragUpdate(widget.session.id, details.globalPosition),
      onPanEnd: (_) => widget.onDragEnd(widget.session.id),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Text(
            '⠿',
            style: TextStyle(
              fontSize: 12,
              color: widget.focused
                  ? _inkOn(widget.accent)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _collapseIcon(Color ink) => Text(
    widget.collapsed ? '⤡' : '⤢',
    style: TextStyle(fontSize: 12, color: ink),
  );

  Widget _title(Color ink) {
    return ValueListenableBuilder(
      valueListenable: widget.session.manualName,
      builder: (context, manualName, child) => ValueListenableBuilder(
        valueListenable: widget.session.name,
        builder: (context, name, child) => ValueListenableBuilder(
          valueListenable: widget.session.activity,
          builder: (context, activity, child) => Text(
            paneTitle(name: name, activity: activity, manualName: manualName),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: widget.focused ? FontWeight.w700 : FontWeight.w400,
              color: ink,
              // Same reasoning as TerminalView's fallback in pane_view.dart:
              // an activity title set via OSC 2 can carry the same dingbat
              // glyphs Claude Code uses in-terminal (✢ ✳ ✻ ✽ ⏺), and without
              // an explicit fallback here the platform's own font cascade
              // substitutes its color emoji font for them.
              fontFamilyFallback: const [
                'Menlo',
                'Monaco',
                'Consolas',
                'Liberation Mono',
                // See terminalFontFamilyFallback's doc comment: none of the
                // fonts above carry ⏺ (U+23FA) in monochrome on stock
                // macOS, so without this entry the OS's own fallback
                // cascade substitutes Apple Color Emoji instead.
                'STIX Two Math',
                'Noto Sans Symbols',
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editField(Color ink) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEditing();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _controller,
        focusNode: _fieldFocusNode,
        style: TextStyle(fontSize: 11, color: ink),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
        ),
        onSubmitted: _commitEditing,
      ),
    );
  }

  void _startEditing() {
    _controller.text = widget.session.manualName.value;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
    // The pane's terminal (session.focusNode) already holds focus in the
    // same scope — right-click reaches PaneView's onPointerDown first, which
    // (re)focuses it — so `autofocus` alone never wins: it is only honoured
    // when nothing else in the scope already holds focus (see
    // workspace_view.dart's _requestFocus doc comment for the same
    // constraint on the terminal side). Deferred to end of frame for the
    // same reason: the field's node is not attached until this rebuild
    // completes.
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (!mounted) return;
      _fieldFocusNode.requestFocus();
    });
  }

  void _commitEditing(String value) {
    widget.session.manualName.value = value.trim();
    setState(() => _editing = false);
  }

  void _cancelEditing() {
    setState(() => _editing = false);
  }
}

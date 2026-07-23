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
class PaneBar extends StatefulWidget {
  const PaneBar({
    super.key,
    required this.session,
    required this.focused,
    required this.canCollapse,
    required this.collapsed,
  });

  static const height = 22.0;

  final Session session;
  final bool focused;
  final bool canCollapse;
  final bool collapsed;

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
      child: Container(
        height: PaneBar.height,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: widget.focused
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainer,
        child: Row(
          children: [
            Expanded(child: _editing ? _editField(scheme) : _title(scheme)),
            if (widget.canCollapse) _collapseIcon(scheme),
          ],
        ),
      ),
    );
  }

  Widget _collapseIcon(ColorScheme scheme) => Text(
    widget.collapsed ? '⤡' : '⤢',
    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
  );

  Widget _title(ColorScheme scheme) {
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
              color: scheme.onSurface,
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
                'Noto Sans Symbols',
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editField(ColorScheme scheme) {
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
        style: TextStyle(fontSize: 11, color: scheme.onSurface),
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

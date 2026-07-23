import 'package:flutter/material.dart';

import 'pane_title.dart';
import 'session.dart';

/// The thin strip naming a pane.
///
/// Carries a title, and — when [canCollapse] is true — a small collapse
/// affordance a tap on the bar (wired by the caller, not here) toggles.
class PaneBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: focused ? scheme.surfaceContainerHighest : scheme.surfaceContainer,
      child: Row(
        children: [
          Expanded(child: _title(scheme)),
          if (canCollapse) _collapseIcon(scheme),
        ],
      ),
    );
  }

  Widget _collapseIcon(ColorScheme scheme) => Text(
    collapsed ? '⤡' : '⤢',
    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
  );

  Widget _title(ColorScheme scheme) {
    return ValueListenableBuilder(
      valueListenable: session.name,
      builder: (context, name, child) => ValueListenableBuilder(
        valueListenable: session.activity,
        builder: (context, activity, child) => Text(
          paneTitle(name: name, activity: activity),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: focused ? FontWeight.w700 : FontWeight.w400,
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
    );
  }
}

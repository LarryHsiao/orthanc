import 'package:flutter/material.dart';

import 'pane_title.dart';
import 'session.dart';

/// The thin strip naming a pane.
///
/// With no tab strip to carry a name, each pane names itself — and that is all
/// this bar does.
class PaneBar extends StatelessWidget {
  const PaneBar({super.key, required this.session, required this.focused});

  static const height = 22.0;

  final Session session;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: focused ? scheme.surfaceContainerHighest : scheme.surfaceContainer,
      child: _title(scheme),
    );
  }

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
          ),
        ),
      ),
    );
  }
}

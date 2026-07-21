import 'package:flutter/material.dart';

import 'session.dart';

/// The thin strip naming a pane.
///
/// With no tab strip to carry a name, each pane names itself — and that is all
/// this bar does. The leading slot holds a spinner only while the session is
/// working, and collapses entirely when it is not, so the glyph always means
/// the one thing: work is happening now.
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
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: focused ? scheme.surfaceContainerHighest : scheme.surfaceContainer,
      child: Row(children: [_spinner(), _title(scheme)]),
    );
  }

  Widget _spinner() {
    return ValueListenableBuilder(
      valueListenable: session.busy,
      builder: (context, busy, child) => busy
          ? const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _title(ColorScheme scheme) {
    return Expanded(
      child: ValueListenableBuilder(
        valueListenable: session.title,
        builder: (context, title, child) => Text(
          title,
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'link_preview_hover.dart';

/// The card's left edge: at [anchorX], pulled back so the whole card stays
/// inside a pane [paneWidth] wide, and never past the pane's own left edge —
/// a pane narrower than the card shows its left part rather than none.
double clampCardLeft({
  required double anchorX,
  required double cardWidth,
  required double paneWidth,
}) {
  final furthest = paneWidth - cardWidth;
  if (furthest <= 0) return 0;
  return anchorX.clamp(0, furthest).toDouble();
}

/// Draws the hovered link's card over the terminal, at its anchor.
///
/// Ignores the pointer entirely, so it never steals the hover or the click
/// from the link beneath. [Positioned.fill] is the outermost widget on
/// purpose: a pane's [Stack] sizes itself to its non-positioned children, and
/// a single stray one would collapse it.
class LinkPreviewOverlay extends StatelessWidget {
  const LinkPreviewOverlay({
    super.key,
    required this.hover,
    required this.textStyle,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final ValueListenable<HoveredPreview?> hover;
  final TextStyle textStyle;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ValueListenableBuilder<HoveredPreview?>(
        valueListenable: hover,
        builder: (context, shown, _) =>
            shown == null ? const SizedBox.shrink() : _placed(shown),
      ),
    );
  }

  Widget _placed(HoveredPreview shown) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final left = clampCardLeft(
            anchorX: shown.anchor.dx,
            cardWidth: LinkPreviewCard.width,
            paneWidth: constraints.maxWidth,
          );
          return Stack(
            children: [
              Positioned(
                left: left,
                top: shown.anchor.dy,
                child: LinkPreviewCard(
                  hovered: shown,
                  textStyle: textStyle,
                  background: background,
                  foreground: foreground,
                  border: border,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One link's card: the site, the page's title, and the link itself.
class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({
    super.key,
    required this.hovered,
    required this.textStyle,
    required this.background,
    required this.foreground,
    required this.border,
  });

  /// Marks the card, for tests.
  static const cardKey = Key('link-preview-card');

  static const width = 300.0;

  /// The site and link lines run smaller than the title, which carries the
  /// card's meaning.
  static const _secondaryScale = 0.85;
  static const _secondaryOpacity = 0.7;

  final HoveredPreview hovered;
  final TextStyle textStyle;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final base = textStyle.copyWith(
      color: foreground,
      decoration: TextDecoration.none,
    );
    final secondary = base.copyWith(
      fontSize: (textStyle.fontSize ?? 14) * _secondaryScale,
      color: foreground.withValues(alpha: _secondaryOpacity),
    );
    return Container(
      key: cardKey,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line(hovered.preview.siteName, secondary),
          _line(
            hovered.preview.title,
            base.copyWith(fontWeight: FontWeight.bold),
          ),
          _line(hovered.url.toString(), secondary),
        ],
      ),
    );
  }

  /// One line, ellipsed when it does not fit — the full value is the link
  /// itself, still reachable by clicking it.
  Widget _line(String text, TextStyle style) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
}

import 'dart:math' as math;
import 'dart:typed_data';

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

/// Where the card's top-left corner goes: under the link's [cell] when it
/// fits there, otherwise above it, otherwise held at the pane's edge so as
/// much of it as possible stays in view. The card is never drawn over the
/// link it describes unless the pane leaves no other choice.
Offset cardOrigin({
  required Rect cell,
  required Size card,
  required Size pane,
}) {
  final left = clampCardLeft(
    anchorX: cell.left,
    cardWidth: card.width,
    paneWidth: pane.width,
  );
  final fitsBelow = cell.bottom + card.height <= pane.height;
  if (fitsBelow) return Offset(left, cell.bottom);
  final above = cell.top - card.height;
  if (above >= 0) return Offset(left, above);
  return Offset(left, math.max(0, pane.height - card.height));
}

/// Draws the hovered link's card — or, while its page is still being
/// fetched, a one-line loading card — over the terminal, beside the link.
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

  final LinkPreviewHover hover;
  final TextStyle textStyle;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: Listenable.merge([hover.shown, hover.loading]),
        builder: (context, _) => _content(),
      ),
    );
  }

  Widget _content() {
    final shown = hover.shown.value;
    final pending = hover.loading.value;
    if (shown != null) {
      return _placed(
        shown.cell,
        LinkPreviewCard(
          hovered: shown,
          textStyle: textStyle,
          background: background,
          foreground: foreground,
          border: border,
        ),
      );
    }
    if (pending == null) return const SizedBox.shrink();
    return _placed(
      pending.cell,
      LinkPreviewLoadingCard(
        textStyle: textStyle,
        background: background,
        foreground: foreground,
        border: border,
      ),
    );
  }

  Widget _placed(Rect cell, Widget card) {
    return IgnorePointer(
      child: CustomSingleChildLayout(delegate: _CardLayout(cell), child: card),
    );
  }
}

class _CardLayout extends SingleChildLayoutDelegate {
  const _CardLayout(this.cell);

  final Rect cell;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      cardOrigin(cell: cell, card: childSize, pane: size);

  @override
  bool shouldRelayout(_CardLayout oldDelegate) => oldDelegate.cell != cell;
}

/// The outline and fill both cards share, with [header] — a picture — flush
/// to the edges above the padded [child].
Widget _cardChrome({
  Key? key,
  required Color background,
  required Color border,
  required Widget child,
  Widget? header,
}) {
  return Container(
    key: key,
    width: LinkPreviewCard.width,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: child,
        ),
      ],
    ),
  );
}

/// One line, ellipsed when it does not fit — the full value is the link
/// itself, still reachable by clicking it.
Widget _line(String text, TextStyle style, {int maxLines = 1}) => Text(
  text,
  maxLines: maxLines,
  overflow: TextOverflow.ellipsis,
  style: style,
);

/// The one-line card shown while a link's page is on its way.
class LinkPreviewLoadingCard extends StatelessWidget {
  const LinkPreviewLoadingCard({
    super.key,
    required this.textStyle,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final TextStyle textStyle;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return _cardChrome(
      key: LinkPreviewCard.loadingKey,
      background: background,
      border: border,
      child: _line(
        'loading…',
        textStyle.copyWith(
          color: foreground.withValues(alpha: LinkPreviewCard.secondaryOpacity),
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

/// One link's card: the site, the page's title and summary, and the link.
class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({
    super.key,
    required this.hovered,
    required this.textStyle,
    required this.background,
    required this.foreground,
    required this.border,
  });

  /// Mark the cards, for tests.
  static const cardKey = Key('link-preview-card');
  static const loadingKey = Key('link-preview-loading');

  static const width = 300.0;

  /// The picture's height; it is cropped to fill the card's width.
  static const imageHeight = 96.0;

  /// The summary is cut after this many lines; a sentence ellipsed any
  /// sooner would lose its meaning.
  static const descriptionLines = 3;

  /// The site and link lines run smaller than the title, which carries the
  /// card's meaning.
  static const secondaryScale = 0.85;
  static const secondaryOpacity = 0.7;

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
      fontSize: (textStyle.fontSize ?? 14) * secondaryScale,
      color: foreground.withValues(alpha: secondaryOpacity),
    );
    return _cardChrome(
      key: cardKey,
      background: background,
      border: border,
      header: _picture(hovered.preview.imageBytes),
      child: _text(base, secondary),
    );
  }

  /// The site, the title, the summary when there is one, and the link.
  Widget _text(TextStyle base, TextStyle secondary) {
    final preview = hovered.preview;
    final description = preview.description;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(preview.siteName, secondary),
        _line(preview.title, base.copyWith(fontWeight: FontWeight.bold)),
        if (description != null)
          _line(description, base, maxLines: descriptionLines),
        _line(hovered.url.toString(), secondary),
      ],
    );
  }

  /// The page's picture, cropped to fill the card; a picture that will not
  /// decode is simply left out.
  Widget? _picture(Uint8List? bytes) {
    if (bytes == null) return null;
    return Image.memory(
      bytes,
      height: imageHeight,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

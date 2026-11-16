import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'link_preview.dart';

/// How long the pointer must rest on a link before its page is fetched.
/// Shorter fires on every link the pointer merely crosses, each one a request
/// to a third-party site.
const defaultHoverDelay = Duration(milliseconds: 400);

/// A preview ready to be drawn: [preview] for [url], anchored at [anchor], the
/// pane-local point where the pointer first met the link.
class HoveredPreview {
  const HoveredPreview({
    required this.url,
    required this.preview,
    required this.anchor,
  });

  final Uri url;
  final LinkPreview preview;
  final Offset anchor;

  @override
  bool operator ==(Object other) =>
      other is HoveredPreview &&
      other.url == url &&
      other.preview == preview &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(url, preview, anchor);
}

/// Decides when a hovered link earns a preview card, and which.
///
/// The pointer must rest on one link for [delay] before [load] is asked for
/// it; moving along the same link does not restart the wait, moving to
/// another does. A result is shown only if the pointer is still on the link
/// it was asked for — leaving, switching links, [clear] and [dispose] all
/// make an in-flight result stale, and a stale one is dropped.
class LinkPreviewHover {
  LinkPreviewHover({required this.load, this.delay = defaultHoverDelay});

  final Future<LinkPreview?> Function(Uri url) load;
  final Duration delay;

  /// The card to draw, or null when none should show.
  final ValueNotifier<HoveredPreview?> shown = ValueNotifier(null);

  Uri? _candidate;
  Offset _anchor = Offset.zero;
  Timer? _timer;

  /// Bumped whenever a pending or in-flight request stops mattering.
  int _generation = 0;

  /// Reports what lies under the pointer: a [link] with the [anchor] to draw
  /// its card at, or null when the pointer is on no previewable link.
  void pointerOver(Uri? link, Offset anchor) {
    if (link == null) return clear();
    if (link == _candidate) return;
    clear();
    _candidate = link;
    _anchor = anchor;
    _timer = Timer(delay, _fire);
  }

  /// Hides the card and abandons any pending or in-flight request.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _candidate = null;
    _generation++;
    shown.value = null;
  }

  void dispose() {
    clear();
    shown.dispose();
  }

  Future<void> _fire() async {
    final link = _candidate;
    if (link == null) return;
    final generation = _generation;
    final preview = await _loadOrNull(link);
    if (generation != _generation || preview == null) return;
    shown.value = HoveredPreview(url: link, preview: preview, anchor: _anchor);
  }

  Future<LinkPreview?> _loadOrNull(Uri link) async {
    try {
      return await load(link);
    } on Object {
      return null;
    }
  }
}

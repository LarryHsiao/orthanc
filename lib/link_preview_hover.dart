import 'dart:async';

import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'link_preview.dart';

/// How long the pointer must rest on a link before its page is fetched.
/// Shorter fires on every link the pointer merely crosses, each one a request
/// to a third-party site.
const defaultHoverDelay = Duration(milliseconds: 400);

/// A link whose preview is being fetched: [url], and the [cell] — the
/// pane-local rectangle of the terminal cell where the pointer first met it,
/// which the card is placed beside.
class PendingLink {
  const PendingLink({required this.url, required this.cell});

  final Uri url;
  final Rect cell;

  @override
  bool operator ==(Object other) =>
      other is PendingLink && other.url == url && other.cell == cell;

  @override
  int get hashCode => Object.hash(url, cell);
}

/// A preview ready to be drawn: [preview] for [url], placed beside [cell].
class HoveredPreview {
  const HoveredPreview({
    required this.url,
    required this.preview,
    required this.cell,
  });

  final Uri url;
  final LinkPreview preview;
  final Rect cell;

  @override
  bool operator ==(Object other) =>
      other is HoveredPreview &&
      other.url == url &&
      other.preview == preview &&
      other.cell == cell;

  @override
  int get hashCode => Object.hash(url, preview, cell);
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

  /// The link whose page is being fetched right now, or null. It ends when
  /// the answer arrives, whatever the answer is — a link with no preview
  /// leaves no card behind.
  final ValueNotifier<PendingLink?> loading = ValueNotifier(null);

  Uri? _candidate;
  Rect _cell = Rect.zero;
  Timer? _timer;

  /// Bumped whenever a pending or in-flight request stops mattering.
  int _generation = 0;

  /// Reports what lies under the pointer: a [link] with the [cell] it was met
  /// in, or null when the pointer is on no previewable link.
  void pointerOver(Uri? link, Rect cell) {
    if (link == null) return clear();
    if (link == _candidate) return;
    clear();
    _candidate = link;
    _cell = cell;
    _timer = Timer(delay, _fire);
  }

  /// Hides the card and abandons any pending or in-flight request.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _candidate = null;
    _generation++;
    shown.value = null;
    loading.value = null;
  }

  void dispose() {
    clear();
    shown.dispose();
    loading.dispose();
  }

  Future<void> _fire() async {
    final link = _candidate;
    if (link == null) return;
    final generation = _generation;
    loading.value = PendingLink(url: link, cell: _cell);
    final preview = await _loadOrNull(link);
    if (generation != _generation) return;
    loading.value = null;
    if (preview == null) return;
    shown.value = HoveredPreview(url: link, preview: preview, cell: _cell);
  }

  Future<LinkPreview?> _loadOrNull(Uri link) async {
    try {
      return await load(link);
    } on Object {
      return null;
    }
  }
}

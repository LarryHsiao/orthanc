import 'link_preview.dart';
import 'link_preview_fetch.dart';
import 'link_preview_policy.dart';
import 'settings.dart';

/// Where a hovered link's preview comes from: the user's settings deciding
/// which links may be fetched at all, and the [LinkPreviewFetcher] doing it.
///
/// The same decision guards the link the pointer rests on and every redirect
/// hop after it, so a permitted link cannot bounce the request to an address
/// the settings forbid.
class LinkPreviewSource {
  const LinkPreviewSource({required this.fetcher, required this.allows});

  /// A source for [settings], or null while link preview is switched off — a
  /// pane given null never starts a hover timer, let alone a request.
  static LinkPreviewSource? forSettings(
    Settings settings,
    LinkPreviewFetcher fetcher,
  ) {
    if (!settings.linkPreviewEnabled) return null;
    return LinkPreviewSource(
      fetcher: fetcher,
      allows: (url) => shouldPreview(url, settings),
    );
  }

  final LinkPreviewFetcher fetcher;

  /// Whether [url] may be fetched; see [shouldPreview].
  final bool Function(String url) allows;

  /// The preview for [url], or null when it is forbidden or has none.
  Future<LinkPreview?> preview(Uri url) {
    if (!allows(url.toString())) return Future.value();
    return fetcher.fetch(url, isAllowed: (hop) => allows(hop.toString()));
  }
}

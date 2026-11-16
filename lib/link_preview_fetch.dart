import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'link_preview.dart';

const defaultFetchTimeout = Duration(seconds: 3);
const defaultFetchMaxBytes = 256 * 1024;
const defaultFetchMaxEntries = 200;

/// Redirect hops followed before giving up.
const _maxRedirects = 5;

/// How much of the body is searched for a `<meta charset>` when the header
/// names none.
const _charsetSniffBytes = 1024;

/// Fetches a page and reads its [LinkPreview], remembering every answer.
///
/// A request is a single GET with a [timeout] over the whole exchange and at
/// most [maxBytes] of body read. A failure of any kind — non-2xx, non-HTML,
/// timeout, network error — is an answer of `null` and is cached like a
/// success, so a dead link is not retried on every hover. The cache keeps the
/// newest [maxEntries] URLs and evicts the oldest.
class LinkPreviewFetcher {
  LinkPreviewFetcher({
    this.timeout = defaultFetchTimeout,
    this.maxBytes = defaultFetchMaxBytes,
    this.maxEntries = defaultFetchMaxEntries,
  });

  final Duration timeout;
  final int maxBytes;
  final int maxEntries;

  // A map literal keeps insertion order, which is what eviction relies on.
  final _cache = <String, Future<LinkPreview?>>{};

  /// The preview for [url], or null when it has none. Concurrent calls for
  /// one URL share a single request.
  ///
  /// Redirects are followed by hand so [isAllowed] can vet every hop: a
  /// permitted link that redirects to a blocked address (a local service, say)
  /// must not be reached through the back door.
  Future<LinkPreview?> fetch(Uri url, {required bool Function(Uri) isAllowed}) {
    final cached = _cache[url.toString()];
    if (cached != null) return cached;
    final pending = _load(url, isAllowed);
    _cache[url.toString()] = pending;
    _evictOldest();
    return pending;
  }

  void _evictOldest() {
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<LinkPreview?> _load(Uri url, bool Function(Uri) isAllowed) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await _follow(client, url, isAllowed).timeout(timeout);
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<LinkPreview?> _follow(
    HttpClient client,
    Uri start,
    bool Function(Uri) isAllowed,
  ) async {
    var url = start;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (!_isWeb(url) || !isAllowed(url)) return null;
      final response = await _get(client, url);
      final next = _redirectTarget(response, url);
      if (next == null) return _preview(response, url);
      url = next;
    }
    return null;
  }

  Future<HttpClientResponse> _get(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.userAgentHeader, 'Orthanc link preview');
    request.headers.set(HttpHeaders.acceptHeader, 'text/html');
    return request.close();
  }

  Uri? _redirectTarget(HttpClientResponse response, Uri from) {
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (!response.isRedirect || location == null) return null;
    return from.resolve(location);
  }

  Future<LinkPreview?> _preview(HttpClientResponse response, Uri url) async {
    final type = response.headers.contentType;
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    final isHtml =
        type?.mimeType == 'text/html' ||
        type?.mimeType == 'application/xhtml+xml';
    if (!ok || !isHtml) return null;
    final bytes = await _readCapped(response);
    final html = _decode(bytes, type?.charset);
    return parseLinkPreview(html, pageUrl: url);
  }

  /// Reads at most [maxBytes], then stops listening so the rest of a large
  /// body is never downloaded.
  Future<Uint8List> _readCapped(Stream<List<int>> body) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body) {
      bytes.add(chunk);
      if (bytes.length >= maxBytes) break;
    }
    final all = bytes.takeBytes();
    return all.length > maxBytes
        ? Uint8List.sublistView(all, 0, maxBytes)
        : all;
  }
}

bool _isWeb(Uri url) => url.scheme == 'http' || url.scheme == 'https';

final _metaCharset = RegExp(
  r'''charset\s*=\s*["']?([\w-]+)''',
  caseSensitive: false,
);

/// Decodes [bytes] by the header's [headerCharset], else a `<meta charset>`
/// in the first bytes, else UTF-8. Only UTF-8 and the Latin-1 family are
/// known; any other charset reads as UTF-8 and may come out garbled — the
/// card then shows odd text rather than failing.
String _decode(Uint8List bytes, String? headerCharset) {
  final sniffed = _metaCharset
      .firstMatch(latin1.decode(bytes.take(_charsetSniffBytes).toList()))
      ?.group(1);
  final charset = (headerCharset ?? sniffed ?? 'utf-8').toLowerCase();
  const latinNames = {'iso-8859-1', 'latin1', 'windows-1252', 'us-ascii'};
  return latinNames.contains(charset)
      ? latin1.decode(bytes)
      : utf8.decode(bytes, allowMalformed: true);
}

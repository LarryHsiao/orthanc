import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'link_preview.dart';

const defaultFetchTimeout = Duration(seconds: 3);
const defaultFetchMaxBytes = 256 * 1024;
const defaultFetchMaxImageBytes = 1024 * 1024;
const defaultFetchMaxEntries = 200;

/// Pictures are up to a megabyte each, so their cache is far smaller than
/// the page cache's.
const defaultFetchMaxImageEntries = 20;

/// Redirect hops followed before giving up.
const _maxRedirects = 5;

/// How much of the body is searched for a `<meta charset>` when the header
/// names none.
const _charsetSniffBytes = 1024;

/// The picture formats a card will show. SVG is left out on purpose: it is a
/// document that can reference further resources, not a bitmap.
const _imageTypes = {'image/png', 'image/jpeg', 'image/gif', 'image/webp'};

/// Fetches a page and reads its [LinkPreview], or fetches a card's picture,
/// remembering every answer.
///
/// A request is a single GET with a [timeout] over the whole exchange. A
/// failure of any kind — non-2xx, the wrong type, timeout, network error — is
/// an answer of `null` and is cached like a success, so a dead link is not
/// retried on every hover. Each cache keeps the newest [maxEntries] URLs and
/// evicts the oldest.
///
/// Redirects are followed by hand so the caller's `isAllowed` can vet every
/// hop: a permitted URL that redirects to a blocked address (a local service,
/// say) must not be reached through the back door. The same holds for a
/// page's image as for the page.
class LinkPreviewFetcher {
  LinkPreviewFetcher({
    this.timeout = defaultFetchTimeout,
    this.maxBytes = defaultFetchMaxBytes,
    this.maxImageBytes = defaultFetchMaxImageBytes,
    this.maxEntries = defaultFetchMaxEntries,
    this.maxImageEntries = defaultFetchMaxImageEntries,
  });

  final Duration timeout;

  /// How much of a page is read; the rest is never downloaded.
  final int maxBytes;

  /// The largest picture accepted. A bigger one is dropped whole, because a
  /// truncated picture is a broken one.
  final int maxImageBytes;
  final int maxEntries;
  final int maxImageEntries;

  // Map literals keep insertion order, which is what eviction relies on.
  final _pages = <String, Future<LinkPreview?>>{};
  final _images = <String, Future<Uint8List?>>{};

  /// The preview for [url], or null when it has none. Concurrent calls for
  /// one URL share a single request.
  Future<LinkPreview?> fetch(Uri url, {required bool Function(Uri) isAllowed}) {
    return _cached(
      _pages,
      maxEntries,
      url,
      () => _run(url, isAllowed, 'text/html', _readPage),
    );
  }

  /// The picture at [url], or null when it is forbidden, not a bitmap of a
  /// known type, over [maxImageBytes], or unreachable.
  Future<Uint8List?> fetchImage(
    Uri url, {
    required bool Function(Uri) isAllowed,
  }) {
    return _cached(
      _images,
      maxImageEntries,
      url,
      () => _run(url, isAllowed, 'image/*', _readImage),
    );
  }

  Future<T?> _cached<T>(
    Map<String, Future<T?>> cache,
    int cap,
    Uri url,
    Future<T?> Function() load,
  ) {
    final cached = cache[url.toString()];
    if (cached != null) return cached;
    final pending = load();
    cache[url.toString()] = pending;
    while (cache.length > cap) {
      cache.remove(cache.keys.first);
    }
    return pending;
  }

  Future<T?> _run<T>(
    Uri url,
    bool Function(Uri) isAllowed,
    String accept,
    Future<T?> Function(HttpClientResponse, Uri) read,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await _follow(
        client,
        url,
        isAllowed,
        accept,
        read,
      ).timeout(timeout);
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<T?> _follow<T>(
    HttpClient client,
    Uri start,
    bool Function(Uri) isAllowed,
    String accept,
    Future<T?> Function(HttpClientResponse, Uri) read,
  ) async {
    var url = start;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (!_isFetchable(url) || !isAllowed(url)) return null;
      final response = await _get(client, url, accept);
      final next = _redirectTarget(response, url);
      if (next == null) return read(response, url);
      url = next;
    }
    return null;
  }

  Future<HttpClientResponse> _get(
    HttpClient client,
    Uri url,
    String accept,
  ) async {
    final request = await client.getUrl(url);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.userAgentHeader, 'Orthanc link preview');
    request.headers.set(HttpHeaders.acceptHeader, accept);
    return request.close();
  }

  Uri? _redirectTarget(HttpClientResponse response, Uri from) {
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (!response.isRedirect || location == null) return null;
    return from.resolve(location);
  }

  Future<LinkPreview?> _readPage(HttpClientResponse response, Uri url) async {
    final type = response.headers.contentType;
    final isHtml =
        type?.mimeType == 'text/html' ||
        type?.mimeType == 'application/xhtml+xml';
    if (!_isSuccess(response) || !isHtml) return null;
    final bytes = await _readUpTo(response, maxBytes);
    final html = _decode(bytes, type?.charset);
    return parseLinkPreview(html, pageUrl: url);
  }

  Future<Uint8List?> _readImage(HttpClientResponse response, Uri url) async {
    final type = response.headers.contentType?.mimeType;
    if (!_isSuccess(response) || !_imageTypes.contains(type)) return null;
    // One byte past the cap is enough to tell "too big" from "exactly fits".
    final bytes = await _readUpTo(response, maxImageBytes + 1);
    return bytes.length > maxImageBytes ? null : bytes;
  }

  bool _isSuccess(HttpClientResponse response) =>
      response.statusCode >= 200 && response.statusCode < 300;

  /// Reads at most [limit] bytes, then stops listening so the rest of a large
  /// body is never downloaded.
  Future<Uint8List> _readUpTo(Stream<List<int>> body, int limit) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body) {
      bytes.add(chunk);
      if (bytes.length >= limit) break;
    }
    final all = bytes.takeBytes();
    return all.length > limit ? Uint8List.sublistView(all, 0, limit) : all;
  }
}

/// http(s) with a host. A URL such as `http:///x` parses but has none, and
/// HttpClient rejects it with an Error that no `on Exception` would catch.
bool _isFetchable(Uri url) =>
    (url.scheme == 'http' || url.scheme == 'https') && url.host.isNotEmpty;

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

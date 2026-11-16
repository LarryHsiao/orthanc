import 'dart:typed_data';

/// What a hover card shows for a link: the Open Graph facts of its page.
class LinkPreview {
  const LinkPreview({
    required this.siteName,
    required this.title,
    this.description,
    this.imageUrl,
    this.imageBytes,
  });

  final String siteName;
  final String title;
  final String? description;

  /// Absolute http(s) URL of the card image, or null when the page names none.
  final String? imageUrl;

  /// The image itself, once fetched through the vetted fetcher. Null when the
  /// page names none, or the image was forbidden, too large, or failed — the
  /// card then simply has no picture.
  final Uint8List? imageBytes;

  /// This preview carrying [bytes] as its picture.
  LinkPreview withImageBytes(Uint8List? bytes) => LinkPreview(
    siteName: siteName,
    title: title,
    description: description,
    imageUrl: imageUrl,
    imageBytes: bytes,
  );

  @override
  bool operator ==(Object other) =>
      other is LinkPreview &&
      other.siteName == siteName &&
      other.title == title &&
      other.description == description &&
      other.imageUrl == imageUrl &&
      _sameBytes(other.imageBytes, imageBytes);

  @override
  int get hashCode => Object.hash(
    siteName,
    title,
    description,
    imageUrl,
    imageBytes?.length,
  );
}

bool _sameBytes(Uint8List? a, Uint8List? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Reads the Open Graph facts out of [html], the page served at [pageUrl].
///
/// Each field falls back through the tags the card's data table names —
/// `og:*`, then `twitter:*`, then the plain HTML equivalent — and a page with
/// no title anywhere yields null, so no card is drawn for it. Only the
/// `<head>` is read, and tags inside HTML comments are ignored. Decoding the
/// bytes to [html] (charset) is the fetcher's concern, not this function's.
LinkPreview? parseLinkPreview(String html, {required Uri pageUrl}) {
  final head = _headOf(html);
  final tags = _metaTags(head);
  final title =
      tags['og:title'] ?? tags['twitter:title'] ?? _titleElement(head);
  if (title == null) return null;
  return LinkPreview(
    siteName: tags['og:site_name'] ?? pageUrl.host,
    title: title,
    description:
        tags['og:description'] ??
        tags['twitter:description'] ??
        tags['description'],
    imageUrl: _absoluteImage(
      tags['og:image'] ?? tags['twitter:image'],
      pageUrl,
    ),
  );
}

final _comment = RegExp(r'<!--.*?-->', dotAll: true);
final _headEnd = RegExp(r'</head\s*>', caseSensitive: false);
// A quoted attribute value may itself hold `>`, so the tag body is a run of
// plain characters or whole quoted strings, not "anything but `>`".
final _metaTag = RegExp(
  r'''<meta\b(?:[^>"']|"[^"]*"|'[^']*')*>''',
  caseSensitive: false,
);
final _attribute = RegExp(
  r'''([a-zA-Z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''',
);
final _titleTag = RegExp(
  r'<title[^>]*>(.*?)</title\s*>',
  caseSensitive: false,
  dotAll: true,
);
final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');
final _whitespace = RegExp(r'\s+');

const _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

String _headOf(String html) {
  final uncommented = html.replaceAll(_comment, '');
  final end = _headEnd.firstMatch(uncommented);
  return end == null ? uncommented : uncommented.substring(0, end.start);
}

/// Maps each meta tag's `property` or `name` (lower-cased) to its cleaned
/// `content`. The first tag for a key wins; an empty content counts as absent.
Map<String, String> _metaTags(String head) {
  final tags = <String, String>{};
  for (final tag in _metaTag.allMatches(head)) {
    final attributes = _attributesOf(tag.group(0)!);
    final key = attributes['property'] ?? attributes['name'];
    final content = _clean(attributes['content']);
    if (key == null || content == null) continue;
    tags.putIfAbsent(key.toLowerCase(), () => content);
  }
  return tags;
}

Map<String, String> _attributesOf(String tag) {
  final attributes = <String, String>{};
  for (final match in _attribute.allMatches(tag)) {
    final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    attributes.putIfAbsent(match.group(1)!.toLowerCase(), () => value);
  }
  return attributes;
}

String? _titleElement(String head) =>
    _clean(_titleTag.firstMatch(head)?.group(1));

/// Decodes entities in one pass (so `&amp;lt;` stays `&lt;`), collapses
/// whitespace, and returns null for what is then empty.
String? _clean(String? raw) {
  if (raw == null) return null;
  final decoded = raw.replaceAllMapped(_entity, _decodeEntity);
  final collapsed = decoded.replaceAll(_whitespace, ' ').trim();
  return collapsed.isEmpty ? null : collapsed;
}

String _decodeEntity(Match match) {
  final body = match.group(1)!;
  if (!body.startsWith('#')) return _namedEntities[body] ?? match.group(0)!;
  final isHex = body.startsWith('#x');
  final code = int.tryParse(
    body.substring(isHex ? 2 : 1),
    radix: isHex ? 16 : 10,
  );
  final valid = code != null && code > 0 && code <= 0x10FFFF;
  return valid ? String.fromCharCode(code) : match.group(0)!;
}

/// Resolves [raw] against [pageUrl]; anything that does not end up http(s)
/// is dropped, so a hostile page cannot point the card at another scheme.
String? _absoluteImage(String? raw, Uri pageUrl) {
  if (raw == null) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  final resolved = pageUrl.resolveUri(uri);
  final isWeb = resolved.scheme == 'http' || resolved.scheme == 'https';
  return isWeb ? resolved.toString() : null;
}

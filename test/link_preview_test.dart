import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/link_preview.dart';

void main() {
  final page = Uri.parse('https://example.com/blog/post');

  LinkPreview? parse(String html) => parseLinkPreview(html, pageUrl: page);

  test('reads every field from Open Graph tags', () {
    const expected = LinkPreview(
      siteName: 'Example',
      title: 'The Title',
      description: 'The summary.',
      imageUrl: 'https://cdn.example.com/cover.png',
    );

    final result = parse('''
<head>
  <meta property="og:site_name" content="Example">
  <meta property="og:title" content="The Title">
  <meta property="og:description" content="The summary.">
  <meta property="og:image" content="https://cdn.example.com/cover.png">
</head>''');

    expect(result, expected);
  });

  test('a content attribute written before property still parses', () {
    const expected = 'Reversed';

    final result = parse('<head><meta content="Reversed" property="og:title">');

    expect(result?.title, expected);
  });

  test('single-quoted and unquoted attribute values parse', () {
    const expected = ['Single', 'bare'];

    final result = parse(
      "<head><meta property='og:title' content='Single'>"
      '<meta property=og:description content=bare>',
    );

    expect([result?.title, result?.description], expected);
  });

  test('tag and attribute names are case-insensitive', () {
    const expected = 'Shouting';

    final result = parse('<HEAD><META PROPERTY="og:title" CONTENT="Shouting">');

    expect(result?.title, expected);
  });

  test('title falls back from og:title to twitter:title', () {
    const expected = 'From Twitter';

    final result = parse(
      '<head><meta name="twitter:title" content="From Twitter">'
      '<title>Plain</title>',
    );

    expect(result?.title, expected);
  });

  test('title falls back to the <title> element', () {
    const expected = 'Plain';

    final result = parse('<head><title>Plain</title></head>');

    expect(result?.title, expected);
  });

  test(
    'description falls back to twitter:description then name=description',
    () {
      const expected = ['tw', 'plain'];

      final first = parse(
        '<head><title>t</title>'
        '<meta name="twitter:description" content="tw">'
        '<meta name="description" content="plain">',
      );
      final second = parse(
        '<head><title>t</title><meta name="description" content="plain">',
      );

      expect([first?.description, second?.description], expected);
    },
  );

  test('image falls back to twitter:image', () {
    const expected = 'https://cdn.example.com/t.png';

    final result = parse(
      '<head><title>t</title>'
      '<meta name="twitter:image" content="https://cdn.example.com/t.png">',
    );

    expect(result?.imageUrl, expected);
  });

  test('site name falls back to the page host', () {
    const expected = 'example.com';

    final result = parse('<head><title>t</title></head>');

    expect(result?.siteName, expected);
  });

  test('a page with no title anywhere yields no preview', () {
    const expected = null;

    final result = parse(
      '<head><meta property="og:description" content="only a summary"></head>',
    );

    expect(result, expected);
  });

  test('a relative image path resolves against the page URL', () {
    const expected = [
      'https://example.com/img.png',
      'https://example.com/blog/img.png',
    ];

    final rooted = parse(
      '<head><title>t</title><meta property="og:image" content="/img.png">',
    );
    final relative = parse(
      '<head><title>t</title><meta property="og:image" content="img.png">',
    );

    expect([rooted?.imageUrl, relative?.imageUrl], expected);
  });

  test('an image that is not http or https is dropped', () {
    const expected = null;

    final result = parse(
      '<head><title>t</title>'
      '<meta property="og:image" content="javascript:alert(1)">',
    );

    expect(result?.imageUrl, expected);
  });

  test('named and numeric entities are decoded once', () {
    const expected = "Tom & Jerry's 中 &lt;";

    final result = parse(
      '<head><meta property="og:title" '
      'content="Tom &amp; Jerry&#39;s &#x4E2D; &amp;lt;">',
    );

    expect(result?.title, expected);
  });

  test('whitespace and newlines inside a title collapse to single spaces', () {
    const expected = 'Two Lines Here';

    final result = parse('<head><title>\n  Two\n   Lines   Here \n</title>');

    expect(result?.title, expected);
  });

  test('CJK text passes through untouched', () {
    const expected = '中文標題：測試';

    final result = parse('<head><title>中文標題：測試</title>');

    expect(result?.title, expected);
  });

  test('tags after </head> are ignored', () {
    const expected = 'Head Title';

    final result = parse(
      '<head><title>Head Title</title></head>'
      '<body><meta property="og:title" content="Body Title"></body>',
    );

    expect(result?.title, expected);
  });

  test('the first of two duplicate tags wins', () {
    const expected = 'First';

    final result = parse(
      '<head><meta property="og:title" content="First">'
      '<meta property="og:title" content="Second">',
    );

    expect(result?.title, expected);
  });

  test('a tag hidden in an HTML comment is ignored', () {
    const expected = 'Real';

    final result = parse(
      '<head><!-- <meta property="og:title" content="Ghost"> -->'
      '<meta property="og:title" content="Real">',
    );

    expect(result?.title, expected);
  });

  test('an empty content attribute counts as missing', () {
    const expected = 'Fallback';

    final result = parse(
      '<head><meta property="og:title" content="">'
      '<title>Fallback</title>',
    );

    expect(result?.title, expected);
  });

  test('a quoted content holding a literal > is not cut short', () {
    const expected = 'a > b and c';

    final result = parse(
      '<head><title>t</title>'
      '<meta property="og:description" content="a > b and c">',
    );

    expect(result?.description, expected);
  });

  test('a missing description and image come back null', () {
    const expected = [null, null];

    final result = parse('<head><title>t</title></head>');

    expect([result?.description, result?.imageUrl], expected);
  });
}

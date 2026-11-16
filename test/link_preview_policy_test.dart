import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/link_preview_policy.dart';
import 'package:orthanc/settings.dart';

void main() {
  const url = 'https://github.com/LarryHsiao/orthanc/pull/42';

  test('a disabled preview never fires, whatever the lists say', () {
    const expected = false;
    const settings = Settings(linkPreviewNever: [], linkPreviewOnly: []);

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('enabled with both lists empty previews any link', () {
    const expected = true;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [],
      linkPreviewOnly: [],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('a Never match blocks the link', () {
    const expected = false;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [r'^https://github\.com/'],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('a link matching no Never line is still previewed', () {
    const expected = true;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [r'^https://gitlab\.com/'],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('a non-empty Only list previews a link that matches it', () {
    const expected = true;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [],
      linkPreviewOnly: [r'^https://github\.com/'],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('a non-empty Only list blocks a link that matches none of it', () {
    const expected = false;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [],
      linkPreviewOnly: [r'^https://docs\.flutter\.dev/'],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('Never wins when a link matches both lists', () {
    const expected = false;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [r'/pull/'],
      linkPreviewOnly: [r'^https://github\.com/'],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('any one matching Only line is enough', () {
    const expected = true;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [],
      linkPreviewOnly: [r'^https://nope\.example/', r'github\.com'],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('the seeded Never list blocks loopback and private addresses', () {
    const expected = [false, false, false, false];
    const settings = Settings(linkPreviewEnabled: true);

    final result = [
      shouldPreview('http://localhost:3000/x', settings),
      shouldPreview('http://127.0.0.1/', settings),
      shouldPreview('https://10.0.0.5/admin', settings),
      shouldPreview('http://192.168.1.5/', settings),
    ];

    expect(result, expected);
  });

  test('the seeded Never list also blocks the other local address ranges', () {
    const expected = [false, false, false, false, false, false];
    const settings = Settings(linkPreviewEnabled: true);

    final result = [
      shouldPreview('http://172.16.0.5/', settings),
      shouldPreview('http://172.31.255.1/', settings),
      shouldPreview('http://169.254.169.254/latest/meta-data', settings),
      shouldPreview('http://[::1]:8080/', settings),
      shouldPreview('http://0.0.0.0/', settings),
      shouldPreview('http://user:pw@127.0.0.1/', settings),
    ];

    expect(result, expected);
  });

  test('the seeded Never list lets a public 172.x address through', () {
    const expected = [true, true];
    const settings = Settings(linkPreviewEnabled: true);

    final result = [
      shouldPreview('http://172.32.0.1/', settings),
      shouldPreview('http://172.15.0.1/', settings),
    ];

    expect(result, expected);
  });

  test('the seeded Never list lets an ordinary site through', () {
    const expected = true;
    const settings = Settings(linkPreviewEnabled: true);

    final result = shouldPreview('https://example.com/', settings);

    expect(result, expected);
  });

  test('blank lines in Never are ignored, not read as match-everything', () {
    const expected = true;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: ['', '   '],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('an Only list of blank lines counts as empty', () {
    const expected = true;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [],
      linkPreviewOnly: ['', '  '],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('an invalid pattern in Never fails closed: no preview', () {
    const expected = false;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [r'^https://(broken'],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });

  test('an invalid pattern in Only fails closed: no preview', () {
    const expected = false;
    const settings = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [],
      linkPreviewOnly: [r'^https://(broken'],
    );

    final result = shouldPreview(url, settings);

    expect(result, expected);
  });
}

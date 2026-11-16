import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/link_preview_fetch.dart';
import 'package:orthanc/link_preview_source.dart';
import 'package:orthanc/settings.dart';

void main() {
  late HttpServer server;
  late Uri base;
  late Map<String, int> hits;
  late Future<void> Function(HttpRequest request) onRequest;

  setUp(() async {
    hits = {};
    onRequest = (request) async => _html(request, '<title>Page</title>');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) {
      hits.update(request.uri.path, (n) => n + 1, ifAbsent: () => 1);
      onRequest(request);
    });
  });

  tearDown(() => server.close(force: true));

  // Loopback is allowed here on purpose: the seeded Never list would block it,
  // and these tests are about the source, not the seed.
  const allowing = Settings(
    linkPreviewEnabled: true,
    linkPreviewNever: [r'/private'],
  );

  test('a link the settings allow is fetched and parsed', () async {
    const expected = 'Page';
    final source = LinkPreviewSource.forSettings(
      allowing,
      LinkPreviewFetcher(),
    )!;

    final result = await source.preview(base.resolve('/p'));

    expect(result?.title, expected);
  });

  test('a link the settings forbid sends no request at all', () async {
    const expected = [null, 0];
    final source = LinkPreviewSource.forSettings(
      allowing,
      LinkPreviewFetcher(),
    )!;

    final result = await source.preview(base.resolve('/private'));

    expect([result, hits.length], expected);
  });

  test(
    'a permitted link that redirects to a forbidden one is not followed',
    () async {
      const expected = [null, null];
      onRequest = (request) async {
        if (request.uri.path == '/a') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set('location', '/private');
          await request.response.close();
          return;
        }
        await _html(request, '<title>Secret</title>');
      };
      final source = LinkPreviewSource.forSettings(
        allowing,
        LinkPreviewFetcher(),
      )!;

      final result = await source.preview(base.resolve('/a'));

      expect([result, hits['/private']], expected);
    },
  );

  test('with link preview switched off there is no source at all', () {
    const expected = null;

    final result = LinkPreviewSource.forSettings(
      const Settings(),
      LinkPreviewFetcher(),
    );

    expect(result, expected);
  });

  test('the Only list is honoured by the source', () async {
    const expected = [null, 0];
    const onlyOther = Settings(
      linkPreviewEnabled: true,
      linkPreviewNever: [],
      linkPreviewOnly: [r'^https://elsewhere\.example/'],
    );
    final source = LinkPreviewSource.forSettings(
      onlyOther,
      LinkPreviewFetcher(),
    )!;

    final result = await source.preview(base.resolve('/p'));

    expect([result, hits.length], expected);
  });
}

Future<void> _html(HttpRequest request, String body) async {
  request.response.headers.contentType = ContentType.html;
  request.response.write(body);
  await request.response.close();
}

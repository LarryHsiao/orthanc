import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/link_preview.dart';
import 'package:orthanc/link_preview_fetch.dart';

void main() {
  late HttpServer server;
  late Uri base;
  late Map<String, int> hits;
  late Future<void> Function(HttpRequest request) onRequest;

  setUp(() async {
    hits = {};
    onRequest = (request) async => _html(request, '<title>Default</title>');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) {
      hits.update(request.uri.path, (n) => n + 1, ifAbsent: () => 1);
      onRequest(request);
    });
  });

  tearDown(() => server.close(force: true));

  bool allowAll(Uri _) => true;

  test('fetches a page and parses its Open Graph card', () async {
    const expected = LinkPreview(
      siteName: 'Site',
      title: 'Hello',
      description: 'World',
    );
    onRequest = (request) async => _html(
      request,
      '<head><meta property="og:site_name" content="Site">'
      '<meta property="og:title" content="Hello">'
      '<meta property="og:description" content="World"></head>',
    );

    final result = await LinkPreviewFetcher().fetch(
      base.resolve('/p'),
      isAllowed: allowAll,
    );

    expect(result, expected);
  });

  test('a second fetch of the same URL is served from the cache', () async {
    const expected = 1;
    final fetcher = LinkPreviewFetcher();

    await fetcher.fetch(base.resolve('/p'), isAllowed: allowAll);
    await fetcher.fetch(base.resolve('/p'), isAllowed: allowAll);

    expect(hits['/p'], expected);
  });

  test('two concurrent fetches of one URL send a single request', () async {
    const expected = 1;
    final fetcher = LinkPreviewFetcher();

    await Future.wait([
      fetcher.fetch(base.resolve('/p'), isAllowed: allowAll),
      fetcher.fetch(base.resolve('/p'), isAllowed: allowAll),
    ]);

    expect(hits['/p'], expected);
  });

  test('a failure is cached too and not retried', () async {
    const expected = [null, 1];
    onRequest = (request) async {
      request.response.statusCode = 500;
      await request.response.close();
    };
    final fetcher = LinkPreviewFetcher();

    final first = await fetcher.fetch(base.resolve('/p'), isAllowed: allowAll);
    await fetcher.fetch(base.resolve('/p'), isAllowed: allowAll);

    expect([first, hits['/p']], expected);
  });

  test('a 404 yields no preview', () async {
    const expected = null;
    onRequest = (request) async {
      request.response.statusCode = 404;
      await request.response.close();
    };

    final result = await LinkPreviewFetcher().fetch(
      base.resolve('/p'),
      isAllowed: allowAll,
    );

    expect(result, expected);
  });

  test('a non-HTML content type yields no preview', () async {
    const expected = null;
    onRequest = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"title":"nope"}');
      await request.response.close();
    };

    final result = await LinkPreviewFetcher().fetch(
      base.resolve('/p'),
      isAllowed: allowAll,
    );

    expect(result, expected);
  });

  test('a scheme other than http or https sends nothing', () async {
    const expected = [null, 0];

    final result = await LinkPreviewFetcher().fetch(
      Uri.parse('ftp://127.0.0.1:${server.port}/p'),
      isAllowed: allowAll,
    );

    expect([result, hits.length], expected);
  });

  test('a response slower than the timeout yields no preview', () async {
    const expected = null;
    onRequest = (request) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      await _html(request, '<title>Late</title>');
    };

    final result = await LinkPreviewFetcher(
      timeout: const Duration(milliseconds: 200),
    ).fetch(base.resolve('/p'), isAllowed: allowAll);

    expect(result, expected);
  });

  test(
    'a title inside the byte cap parses though the body runs far past it',
    () async {
      const expected = 'Early';
      onRequest = (request) async =>
          _html(request, '<head><title>Early</title></head>${'x' * 200000}');

      final result = await LinkPreviewFetcher(
        maxBytes: 1024,
      ).fetch(base.resolve('/p'), isAllowed: allowAll);

      expect(result?.title, expected);
    },
  );

  test('a title that lies past the byte cap is never read', () async {
    const expected = null;
    onRequest = (request) async =>
        _html(request, '<head>${'x' * 5000}<title>Late</title></head>');

    final result = await LinkPreviewFetcher(
      maxBytes: 1024,
    ).fetch(base.resolve('/p'), isAllowed: allowAll);

    expect(result, expected);
  });

  test('a redirect is followed and the final page is parsed', () async {
    const expected = 'Landed';
    onRequest = (request) async {
      if (request.uri.path == '/a') return _redirect(request, '/b');
      await _html(request, '<title>Landed</title>');
    };

    final result = await LinkPreviewFetcher().fetch(
      base.resolve('/a'),
      isAllowed: allowAll,
    );

    expect(result?.title, expected);
  });

  test('a redirect to a disallowed address is not followed', () async {
    const expected = [null, null];
    onRequest = (request) async {
      if (request.uri.path == '/a') return _redirect(request, '/private');
      await _html(request, '<title>Secret</title>');
    };

    final result = await LinkPreviewFetcher().fetch(
      base.resolve('/a'),
      isAllowed: (uri) => uri.path != '/private',
    );

    expect([result, hits['/private']], expected);
  });

  test('a redirect loop gives up with no preview', () async {
    const expected = null;
    onRequest = (request) async => _redirect(request, request.uri.path);

    final result = await LinkPreviewFetcher().fetch(
      base.resolve('/loop'),
      isAllowed: allowAll,
    );

    expect(result, expected);
  });

  test(
    'the charset named in the Content-Type header decodes the body',
    () async {
      const expected = 'café';
      onRequest = (request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'html',
          charset: 'iso-8859-1',
        );
        request.response.add(latin1.encode('<title>café</title>'));
        await request.response.close();
      };

      final result = await LinkPreviewFetcher().fetch(
        base.resolve('/p'),
        isAllowed: allowAll,
      );

      expect(result?.title, expected);
    },
  );

  test('a meta charset decodes the body when the header names none', () async {
    const expected = 'café';
    onRequest = (request) async {
      request.response.headers.set('content-type', 'text/html');
      request.response.add(
        latin1.encode('<head><meta charset="iso-8859-1"><title>café</title>'),
      );
      await request.response.close();
    };

    final result = await LinkPreviewFetcher().fetch(
      base.resolve('/p'),
      isAllowed: allowAll,
    );

    expect(result?.title, expected);
  });

  test('with no charset anywhere the body decodes as UTF-8', () async {
    const expected = '中文';
    onRequest = (request) async {
      request.response.headers.set('content-type', 'text/html');
      request.response.add(utf8.encode('<title>中文</title>'));
      await request.response.close();
    };

    final result = await LinkPreviewFetcher().fetch(
      base.resolve('/p'),
      isAllowed: allowAll,
    );

    expect(result?.title, expected);
  });

  group('fetchImage', () {
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
      '60e6kgAAAABJRU5ErkJggg==',
    );

    Future<void> image(
      HttpRequest request, {
      ContentType? type,
      List<int>? body,
    }) async {
      request.response.headers.contentType = type ?? ContentType('image', 'png');
      request.response.add(body ?? pngBytes);
      await request.response.close();
    }

    test('returns the bytes of a PNG', () async {
      onRequest = (request) => image(request);

      final result = await LinkPreviewFetcher().fetchImage(
        base.resolve('/i.png'),
        isAllowed: allowAll,
      );

      expect(result, pngBytes);
    });

    test('a second fetch of the same image is served from the cache', () async {
      const expected = 1;
      onRequest = (request) => image(request);
      final fetcher = LinkPreviewFetcher();

      await fetcher.fetchImage(base.resolve('/i.png'), isAllowed: allowAll);
      await fetcher.fetchImage(base.resolve('/i.png'), isAllowed: allowAll);

      expect(hits['/i.png'], expected);
    });

    test('a page and an image under one URL do not share a cache entry', () async {
      const expected = [true, true];
      onRequest = (request) async {
        if (request.headers.value('accept') == 'image/*') {
          return image(request);
        }
        await _html(request, '<title>Page</title>');
      };
      final fetcher = LinkPreviewFetcher();

      final page = await fetcher.fetch(base.resolve('/x'), isAllowed: allowAll);
      final img = await fetcher.fetchImage(
        base.resolve('/x'),
        isAllowed: allowAll,
      );

      expect([page != null, img != null], expected);
    });

    test('an HTML response is not accepted as an image', () async {
      const expected = null;
      onRequest = (request) => _html(request, '<title>not an image</title>');

      final result = await LinkPreviewFetcher().fetchImage(
        base.resolve('/i.png'),
        isAllowed: allowAll,
      );

      expect(result, expected);
    });

    test('an SVG is refused', () async {
      const expected = null;
      onRequest = (request) => image(
        request,
        type: ContentType('image', 'svg+xml'),
        body: utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'),
      );

      final result = await LinkPreviewFetcher().fetchImage(
        base.resolve('/i.svg'),
        isAllowed: allowAll,
      );

      expect(result, expected);
    });

    test('an image over the byte cap is dropped whole, not truncated', () async {
      const expected = null;
      onRequest = (request) => image(request, body: List.filled(500, 1));

      final result = await LinkPreviewFetcher(maxImageBytes: 100).fetchImage(
        base.resolve('/i.png'),
        isAllowed: allowAll,
      );

      expect(result, expected);
    });

    test('an image exactly at the byte cap is kept', () async {
      const expected = 100;
      onRequest = (request) => image(request, body: List.filled(100, 1));

      final result = await LinkPreviewFetcher(maxImageBytes: 100).fetchImage(
        base.resolve('/i.png'),
        isAllowed: allowAll,
      );

      expect(result?.length, expected);
    });

    test('a 404 yields no image', () async {
      const expected = null;
      onRequest = (request) async {
        request.response.statusCode = 404;
        await request.response.close();
      };

      final result = await LinkPreviewFetcher().fetchImage(
        base.resolve('/i.png'),
        isAllowed: allowAll,
      );

      expect(result, expected);
    });

    test('a redirect to a disallowed address is not followed', () async {
      const expected = [null, null];
      onRequest = (request) async {
        if (request.uri.path == '/a.png') {
          return _redirect(request, '/private.png');
        }
        await image(request);
      };

      final result = await LinkPreviewFetcher().fetchImage(
        base.resolve('/a.png'),
        isAllowed: (uri) => uri.path != '/private.png',
      );

      expect([result, hits['/private.png']], expected);
    });

    test('a slow image yields none', () async {
      const expected = null;
      onRequest = (request) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        await image(request);
      };

      final result = await LinkPreviewFetcher(
        timeout: const Duration(milliseconds: 200),
      ).fetchImage(base.resolve('/i.png'), isAllowed: allowAll);

      expect(result, expected);
    });
  });

  group('a URL with no host', () {
    test('a page URL with no host yields none without throwing', () async {
      const expected = null;

      final result = await LinkPreviewFetcher().fetch(
        Uri.parse('http:///x'),
        isAllowed: allowAll,
      );

      expect(result, expected);
    });

    test('an image URL with no host yields none without throwing', () async {
      const expected = null;

      final result = await LinkPreviewFetcher().fetchImage(
        Uri.parse('http:///x'),
        isAllowed: allowAll,
      );

      expect(result, expected);
    });

    test('a redirect to a URL with no host yields none', () async {
      const expected = null;
      onRequest = (request) async {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set('location', 'http:///x');
        await request.response.close();
      };

      final result = await LinkPreviewFetcher().fetch(
        base.resolve('/a'),
        isAllowed: allowAll,
      );

      expect(result, expected);
    });
  });

  test('the image cache evicts on its own, smaller cap', () async {
    const expected = 2;
    onRequest = (request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add([1, 2, 3]);
      await request.response.close();
    };
    final fetcher = LinkPreviewFetcher(maxImageEntries: 1);

    await fetcher.fetchImage(base.resolve('/a.png'), isAllowed: allowAll);
    await fetcher.fetchImage(base.resolve('/b.png'), isAllowed: allowAll);
    await fetcher.fetchImage(base.resolve('/a.png'), isAllowed: allowAll);

    expect(hits['/a.png'], expected);
  });

  test('the oldest cache entry is evicted once the cap is exceeded', () async {
    const expected = 2;
    final fetcher = LinkPreviewFetcher(maxEntries: 1);

    await fetcher.fetch(base.resolve('/a'), isAllowed: allowAll);
    await fetcher.fetch(base.resolve('/b'), isAllowed: allowAll);
    await fetcher.fetch(base.resolve('/a'), isAllowed: allowAll);

    expect(hits['/a'], expected);
  });
}

Future<void> _html(HttpRequest request, String body) async {
  request.response.headers.contentType = ContentType.html;
  request.response.write(body);
  await request.response.close();
}

Future<void> _redirect(HttpRequest request, String location) async {
  request.response.statusCode = HttpStatus.found;
  request.response.headers.set('location', location);
  await request.response.close();
}

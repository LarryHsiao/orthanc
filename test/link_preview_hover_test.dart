import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/link_preview.dart';
import 'package:orthanc/link_preview_hover.dart';

void main() {
  final linkA = Uri.parse('https://a.example/page');
  final linkB = Uri.parse('https://b.example/page');
  const previewA = LinkPreview(siteName: 'A', title: 'Title A');
  const previewB = LinkPreview(siteName: 'B', title: 'Title B');
  const cell = Rect.fromLTWH(40, 80, 10, 20);
  const delay = defaultHoverDelay;

  late List<Uri> loaded;
  late Map<Uri, Completer<LinkPreview?>> pending;
  late LinkPreviewHover hover;

  setUp(() {
    loaded = [];
    pending = {};
    hover = LinkPreviewHover(
      load: (url) {
        loaded.add(url);
        return (pending[url] = Completer<LinkPreview?>()).future;
      },
    );
    addTearDown(hover.dispose);
  });

  Future<void> advance(WidgetTester tester, Duration by) => tester.pump(by);

  testWidgets('nothing is loaded before the delay elapses', (tester) async {
    const expected = <Uri>[];
    hover.pointerOver(linkA, cell);

    await advance(tester, delay - const Duration(milliseconds: 1));

    expect(loaded, expected);
    // This test stops one tick short of the timer, so cancel it before
    // testWidgets checks that none is left pending.
    hover.clear();
  });

  testWidgets('the link is loaded once the delay has elapsed', (tester) async {
    final expected = [linkA];
    hover.pointerOver(linkA, cell);

    await advance(tester, delay);

    expect(loaded, expected);
  });

  testWidgets('a loaded preview is shown with its link and cell', (
    tester,
  ) async {
    final expected = HoveredPreview(
      url: linkA,
      preview: previewA,
      cell: cell,
    );
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);

    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    expect(hover.shown.value, expected);
  });

  testWidgets('moving within the same link does not restart the timer', (
    tester,
  ) async {
    final expected = [linkA];
    hover.pointerOver(linkA, cell);
    await advance(tester, const Duration(milliseconds: 300));
    hover.pointerOver(linkA, const Rect.fromLTWH(60, 80, 10, 20));

    await advance(tester, delay - const Duration(milliseconds: 300));

    expect(loaded, expected);
  });

  testWidgets('moving to another link restarts the delay for that link', (
    tester,
  ) async {
    final expected = [linkB];
    hover.pointerOver(linkA, cell);
    await advance(tester, const Duration(milliseconds: 300));
    hover.pointerOver(linkB, cell);

    await advance(tester, delay);

    expect(loaded, expected);
  });

  testWidgets('leaving the link before the delay cancels the load', (
    tester,
  ) async {
    const expected = <Uri>[];
    hover.pointerOver(linkA, cell);
    await advance(tester, const Duration(milliseconds: 200));

    hover.pointerOver(null, cell);
    await advance(tester, delay);

    expect(loaded, expected);
  });

  testWidgets('leaving the link after the card shows hides it', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);
    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    hover.pointerOver(null, cell);

    expect(hover.shown.value, expected);
  });

  testWidgets('a result arriving after the pointer left is dropped', (
    tester,
  ) async {
    const expected = null;
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);
    hover.pointerOver(null, cell);

    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    expect(hover.shown.value, expected);
  });

  testWidgets('a result for an earlier link never replaces the current one', (
    tester,
  ) async {
    final expected = HoveredPreview(
      url: linkB,
      preview: previewB,
      cell: cell,
    );
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);
    hover.pointerOver(linkB, cell);
    await advance(tester, delay);

    pending[linkB]!.complete(previewB);
    await advance(tester, Duration.zero);
    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    expect(hover.shown.value, expected);
  });

  testWidgets('a link with no preview shows nothing', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);

    pending[linkA]!.complete(null);
    await advance(tester, Duration.zero);

    expect(hover.shown.value, expected);
  });

  testWidgets('a failed load shows nothing and does not throw', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);

    pending[linkA]!.completeError(StateError('boom'));
    await advance(tester, Duration.zero);

    expect(hover.shown.value, expected);
  });

  testWidgets('clear hides the card and lets the same link load again', (
    tester,
  ) async {
    final expected = [linkA, linkA];
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);
    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    hover.clear();
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);

    expect(loaded, expected);
    expect(hover.shown.value, isNull);
  });

  testWidgets('while a request is in flight the link is reported as loading', (
    tester,
  ) async {
    final expected = [linkA, cell];
    hover.pointerOver(linkA, cell);

    await advance(tester, delay);

    expect([hover.loading.value?.url, hover.loading.value?.cell], expected);
  });

  testWidgets('nothing is loading before the delay has elapsed', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, cell);

    await advance(tester, delay - const Duration(milliseconds: 1));

    expect(hover.loading.value, expected);
    hover.clear();
  });

  testWidgets('loading ends when the preview arrives', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);

    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    expect(hover.loading.value, expected);
  });

  testWidgets('loading ends when the link turns out to have no preview', (
    tester,
  ) async {
    const expected = null;
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);

    pending[linkA]!.complete(null);
    await advance(tester, Duration.zero);

    expect(hover.loading.value, expected);
  });

  testWidgets('loading ends when the request fails', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);

    pending[linkA]!.completeError(StateError('boom'));
    await advance(tester, Duration.zero);

    expect(hover.loading.value, expected);
  });

  testWidgets('loading ends when the pointer leaves the link', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);

    hover.pointerOver(null, cell);

    expect(hover.loading.value, expected);
  });

  testWidgets('moving to another link replaces what is loading', (tester) async {
    hover.pointerOver(linkA, cell);
    await advance(tester, delay);

    hover.pointerOver(linkB, cell);
    await advance(tester, delay);

    expect(hover.loading.value?.url, linkB);
  });

  testWidgets('disposing cancels a pending load', (tester) async {
    const expected = <Uri>[];
    final local = <Uri>[];
    final other = LinkPreviewHover(
      load: (url) {
        local.add(url);
        return Future.value(null);
      },
    );
    other.pointerOver(linkA, cell);

    other.dispose();
    await advance(tester, delay);

    expect(local, expected);
  });
}

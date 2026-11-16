import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/link_preview.dart';
import 'package:orthanc/link_preview_hover.dart';

void main() {
  final linkA = Uri.parse('https://a.example/page');
  final linkB = Uri.parse('https://b.example/page');
  const previewA = LinkPreview(siteName: 'A', title: 'Title A');
  const previewB = LinkPreview(siteName: 'B', title: 'Title B');
  const anchor = Offset(40, 80);
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
    hover.pointerOver(linkA, anchor);

    await advance(tester, delay - const Duration(milliseconds: 1));

    expect(loaded, expected);
    // This test stops one tick short of the timer, so cancel it before
    // testWidgets checks that none is left pending.
    hover.clear();
  });

  testWidgets('the link is loaded once the delay has elapsed', (tester) async {
    final expected = [linkA];
    hover.pointerOver(linkA, anchor);

    await advance(tester, delay);

    expect(loaded, expected);
  });

  testWidgets('a loaded preview is shown with its link and anchor', (
    tester,
  ) async {
    final expected = HoveredPreview(
      url: linkA,
      preview: previewA,
      anchor: anchor,
    );
    hover.pointerOver(linkA, anchor);
    await advance(tester, delay);

    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    expect(hover.shown.value, expected);
  });

  testWidgets('moving within the same link does not restart the timer', (
    tester,
  ) async {
    final expected = [linkA];
    hover.pointerOver(linkA, anchor);
    await advance(tester, const Duration(milliseconds: 300));
    hover.pointerOver(linkA, const Offset(60, 80));

    await advance(tester, delay - const Duration(milliseconds: 300));

    expect(loaded, expected);
  });

  testWidgets('moving to another link restarts the delay for that link', (
    tester,
  ) async {
    final expected = [linkB];
    hover.pointerOver(linkA, anchor);
    await advance(tester, const Duration(milliseconds: 300));
    hover.pointerOver(linkB, anchor);

    await advance(tester, delay);

    expect(loaded, expected);
  });

  testWidgets('leaving the link before the delay cancels the load', (
    tester,
  ) async {
    const expected = <Uri>[];
    hover.pointerOver(linkA, anchor);
    await advance(tester, const Duration(milliseconds: 200));

    hover.pointerOver(null, anchor);
    await advance(tester, delay);

    expect(loaded, expected);
  });

  testWidgets('leaving the link after the card shows hides it', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, anchor);
    await advance(tester, delay);
    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    hover.pointerOver(null, anchor);

    expect(hover.shown.value, expected);
  });

  testWidgets('a result arriving after the pointer left is dropped', (
    tester,
  ) async {
    const expected = null;
    hover.pointerOver(linkA, anchor);
    await advance(tester, delay);
    hover.pointerOver(null, anchor);

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
      anchor: anchor,
    );
    hover.pointerOver(linkA, anchor);
    await advance(tester, delay);
    hover.pointerOver(linkB, anchor);
    await advance(tester, delay);

    pending[linkB]!.complete(previewB);
    await advance(tester, Duration.zero);
    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    expect(hover.shown.value, expected);
  });

  testWidgets('a link with no preview shows nothing', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, anchor);
    await advance(tester, delay);

    pending[linkA]!.complete(null);
    await advance(tester, Duration.zero);

    expect(hover.shown.value, expected);
  });

  testWidgets('a failed load shows nothing and does not throw', (tester) async {
    const expected = null;
    hover.pointerOver(linkA, anchor);
    await advance(tester, delay);

    pending[linkA]!.completeError(StateError('boom'));
    await advance(tester, Duration.zero);

    expect(hover.shown.value, expected);
  });

  testWidgets('clear hides the card and lets the same link load again', (
    tester,
  ) async {
    final expected = [linkA, linkA];
    hover.pointerOver(linkA, anchor);
    await advance(tester, delay);
    pending[linkA]!.complete(previewA);
    await advance(tester, Duration.zero);

    hover.clear();
    hover.pointerOver(linkA, anchor);
    await advance(tester, delay);

    expect(loaded, expected);
    expect(hover.shown.value, null);
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
    other.pointerOver(linkA, anchor);

    other.dispose();
    await advance(tester, delay);

    expect(local, expected);
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/link_preview.dart';
import 'package:orthanc/link_preview_card.dart';
import 'package:orthanc/link_preview_fetch.dart';
import 'package:orthanc/link_preview_hover.dart';
import 'package:orthanc/link_preview_source.dart';
import 'package:orthanc/pane_view.dart';
import 'package:orthanc/session.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/terminal_color_schemes.dart';
import 'package:orthanc/terminal_font_families.dart';
import 'package:xterm/xterm.dart';

/// A source that answers instantly and records what it was asked for, so a
/// pane's hover wiring can be tested without a network.
class _FakeSource extends LinkPreviewSource {
  _FakeSource(this.result)
    : super(fetcher: LinkPreviewFetcher(), allows: (_) => true);

  final LinkPreview? result;
  final requested = <Uri>[];

  @override
  Future<LinkPreview?> preview(Uri url) {
    requested.add(url);
    return Future.value(result);
  }
}

void main() {
  final theme = terminalThemeFor(TerminalColorScheme.dracula);
  const preview = LinkPreview(siteName: 'Example Site', title: 'Hello Title');
  const link = 'https://example.com/article';

  String osc8(String url, String text) =>
      '\x1b]8;;$url\x1b\\$text\x1b]8;;\x1b\\';

  Future<void> pumpPane(
    WidgetTester tester,
    Session session, {
    LinkPreviewSource? source,
    FocusOnKeyEventCallback? onKeyEvent,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaneView(
            session: session,
            focused: true,
            onFocus: () {},
            onKeyEvent: onKeyEvent ?? (node, event) => KeyEventResult.ignored,
            canCollapse: false,
            collapsed: false,
            theme: theme,
            fontFamily: terminalFontFamilyName(
              TerminalFontFamily.defaultFamily,
            ),
            fontSize: defaultTerminalFontSize,
            onToggleCollapse: () {},
            onExpand: () {},
            canDrag: false,
            onDragStart: (_) {},
            onDragUpdate: (_, _) {},
            onDragEnd: (_) {},
            isDropTarget: false,
            isBeingDragged: false,
            dropSide: null,
            isFileDropTarget: false,
            linkPreview: source,
          ),
        ),
      ),
    );
  }

  Future<Session> pumpWithText(
    WidgetTester tester,
    String text, {
    LinkPreviewSource? source,
    FocusOnKeyEventCallback? onKeyEvent,
  }) async {
    final session = Session(id: 'a', executable: 'cmd.exe');
    addTearDown(session.dispose);
    session.terminal.write(text);
    await pumpPane(tester, session, source: source, onKeyEvent: onKeyEvent);
    await tester.pump();
    return session;
  }

  /// The pane-global position of the middle of the text's first row, a few
  /// cells in.
  Offset onFirstRow(WidgetTester tester, {int column = 2}) {
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    final cell = state.renderTerminal.cellSize;
    final origin = tester.getTopLeft(find.byType(TerminalView));
    return origin + Offset(cell.width * (column + 0.5), cell.height * 0.5);
  }

  Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(position);
    return mouse;
  }

  Future<void> restOnLink(WidgetTester tester) async {
    await tester.pump(defaultHoverDelay);
    await tester.pump();
  }

  testWidgets('resting on a link shows its card after the delay', (
    tester,
  ) async {
    const expected = true;
    await pumpWithText(
      tester,
      osc8(link, 'click here'),
      source: _FakeSource(preview),
    );

    await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    expect(find.byKey(LinkPreviewCard.cardKey).evaluate().isNotEmpty, expected);
  });

  testWidgets('no card shows before the delay has elapsed', (tester) async {
    const expected = false;
    final source = _FakeSource(preview);
    await pumpWithText(tester, osc8(link, 'click here'), source: source);

    await mouseAt(tester, onFirstRow(tester));
    await tester.pump(defaultHoverDelay - const Duration(milliseconds: 1));

    expect(find.byKey(LinkPreviewCard.cardKey).evaluate().isNotEmpty, expected);
    await tester.pump(defaultHoverDelay);
  });

  testWidgets('the card names the site, the title and the link', (
    tester,
  ) async {
    const expected = [true, true, true];
    await pumpWithText(
      tester,
      osc8(link, 'click here'),
      source: _FakeSource(preview),
    );

    await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    final result = [
      find.text('Example Site').evaluate().isNotEmpty,
      find.text('Hello Title').evaluate().isNotEmpty,
      find.text(link).evaluate().isNotEmpty,
    ];
    expect(result, expected);
  });

  testWidgets('the link is requested without any modifier key held', (
    tester,
  ) async {
    final expected = [Uri.parse(link)];
    final source = _FakeSource(preview);
    await pumpWithText(tester, osc8(link, 'click here'), source: source);

    await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    expect(source.requested, expected);
  });

  testWidgets('with no source nothing is shown', (tester) async {
    const expected = false;
    await pumpWithText(tester, osc8(link, 'click here'));

    await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    expect(find.byKey(LinkPreviewCard.cardKey).evaluate().isNotEmpty, expected);
  });

  testWidgets('plain text under the pointer requests nothing', (tester) async {
    const expected = <Uri>[];
    final source = _FakeSource(preview);
    await pumpWithText(tester, 'just plain words', source: source);

    await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    expect(source.requested, expected);
  });

  testWidgets('a link that is not http or https requests nothing', (
    tester,
  ) async {
    const expected = <Uri>[];
    final source = _FakeSource(preview);
    await pumpWithText(
      tester,
      osc8('file:///etc/passwd', 'local file'),
      source: source,
    );

    await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    expect(source.requested, expected);
  });

  testWidgets('a link with no preview shows no card', (tester) async {
    const expected = false;
    await pumpWithText(
      tester,
      osc8(link, 'click here'),
      source: _FakeSource(null),
    );

    await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    expect(find.byKey(LinkPreviewCard.cardKey).evaluate().isNotEmpty, expected);
  });

  testWidgets('moving off the link hides the card', (tester) async {
    const expected = false;
    await pumpWithText(
      tester,
      osc8(link, 'click here'),
      source: _FakeSource(preview),
    );
    final mouse = await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    await mouse.moveTo(onFirstRow(tester, column: 40));
    await tester.pump();

    expect(find.byKey(LinkPreviewCard.cardKey).evaluate().isNotEmpty, expected);
  });

  testWidgets('the pointer leaving the pane hides the card', (tester) async {
    const expected = false;
    await pumpWithText(
      tester,
      osc8(link, 'click here'),
      source: _FakeSource(preview),
    );
    final mouse = await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    await mouse.moveTo(const Offset(5000, 5000));
    await tester.pump();

    expect(find.byKey(LinkPreviewCard.cardKey).evaluate().isNotEmpty, expected);
  });

  testWidgets('a key press hides the card', (tester) async {
    const expected = false;
    final session = await pumpWithText(
      tester,
      osc8(link, 'click here'),
      source: _FakeSource(preview),
    );
    session.focusNode.requestFocus();
    await tester.pump();
    await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();

    expect(find.byKey(LinkPreviewCard.cardKey).evaluate().isNotEmpty, expected);
  });

  testWidgets('a press inside the pane hides the card', (tester) async {
    const expected = false;
    await pumpWithText(
      tester,
      osc8(link, 'click here'),
      source: _FakeSource(preview),
    );
    final mouse = await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    await mouse.down(onFirstRow(tester));
    await mouse.up();
    await tester.pump();

    expect(find.byKey(LinkPreviewCard.cardKey).evaluate().isNotEmpty, expected);
    // Releasing re-reports the pointer on the link, which arms a fresh
    // timer; let it run out before testWidgets checks none is pending.
    await tester.pump(defaultHoverDelay);
  });

  testWidgets('switching the source off removes a card already showing', (
    tester,
  ) async {
    const expected = false;
    final session = await pumpWithText(
      tester,
      osc8(link, 'click here'),
      source: _FakeSource(preview),
    );
    await mouseAt(tester, onFirstRow(tester));
    await restOnLink(tester);

    await pumpPane(tester, session);
    await tester.pump();

    expect(find.byKey(LinkPreviewCard.cardKey).evaluate().isNotEmpty, expected);
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/session.dart';

void main() {
  test('stores the id and executable it is given', () {
    const expectedId = 'a';
    const expectedExecutable = 'cmd.exe';

    final session = Session(id: expectedId, executable: expectedExecutable);

    expect(session.id, expectedId);
    expect(session.executable, expectedExecutable);
  });

  test('starts with its activity set to its executable', () {
    const expectedActivity = 'cmd.exe';

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.activity.value, expectedActivity);
  });

  test('starts with no name', () {
    const expectedName = '';

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.name.value, expectedName);
  });

  test('starts with no manual name', () {
    const expectedManualName = '';

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.manualName.value, expectedManualName);
  });

  test('starts with needsAttention false', () {
    const expected = false;

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.needsAttention.value, expected);
  });

  test('a single activity change never arms needsAttention', () {
    fakeAsync((async) {
      const expected = false;
      final session = Session(id: 'a', executable: 'cmd.exe');

      session.activity.value = 'thinking';
      async.elapse(const Duration(seconds: 3));

      expect(session.needsAttention.value, expected);
    });
  });

  test('two activity changes further apart than the burst window never arm '
      'needsAttention', () {
    fakeAsync((async) {
      const expected = false;
      final session = Session(id: 'a', executable: 'cmd.exe');

      session.activity.value = 'thinking';
      async.elapse(const Duration(seconds: 2));
      session.activity.value = 'still thinking';
      async.elapse(const Duration(seconds: 3));

      expect(session.needsAttention.value, expected);
    });
  });

  test('a burst of activity followed by quiet sets needsAttention, once '
      'unfocused', () {
    fakeAsync((async) {
      const expected = true;
      final session = Session(id: 'a', executable: 'cmd.exe');

      session.activity.value = 'thinking';
      async.elapse(const Duration(milliseconds: 900));
      session.activity.value = 'still thinking';
      async.elapse(const Duration(seconds: 3));

      expect(session.needsAttention.value, expected);
    });
  });

  test('needsAttention does not fire before the quiet threshold elapses', () {
    fakeAsync((async) {
      const expected = false;
      final session = Session(id: 'a', executable: 'cmd.exe');

      session.activity.value = 'thinking';
      async.elapse(const Duration(milliseconds: 900));
      session.activity.value = 'still thinking';
      async.elapse(const Duration(milliseconds: 500));

      expect(session.needsAttention.value, expected);
    });
  });

  testWidgets('needsAttention never fires while the pane is focused', (
    tester,
  ) async {
    const expected = false;
    final session = Session(id: 'a', executable: 'cmd.exe');
    addTearDown(session.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Focus(focusNode: session.focusNode, child: const SizedBox()),
      ),
    );
    session.focusNode.requestFocus();
    await tester.pump();
    expect(session.focusNode.hasFocus, isTrue);

    session.activity.value = 'thinking';
    await tester.pump(const Duration(milliseconds: 900));
    session.activity.value = 'still thinking';
    await tester.pump(const Duration(seconds: 3));

    expect(session.needsAttention.value, expected);
  });

  testWidgets('gaining focus clears an already-set needsAttention flag', (
    tester,
  ) async {
    const expected = false;
    final session = Session(id: 'a', executable: 'cmd.exe');
    addTearDown(session.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Focus(focusNode: session.focusNode, child: const SizedBox()),
      ),
    );
    session.needsAttention.value = true;

    session.focusNode.requestFocus();
    await tester.pump();

    expect(session.needsAttention.value, expected);
  });

  test('dispose() cancels a pending quiet timer without throwing', () {
    fakeAsync((async) {
      final session = Session(id: 'a', executable: 'cmd.exe');
      session.activity.value = 'thinking';
      async.elapse(const Duration(milliseconds: 900));
      session.activity.value = 'still thinking';

      expect(session.dispose, returnsNormally);
      async.elapse(const Duration(seconds: 3));
    });
  });

  test('dispose() on a never-started session does not throw', () {
    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.dispose, returnsNormally);
  });

  test('dispose() is safe to call twice', () {
    final session = Session(id: 'a', executable: 'cmd.exe');
    session.dispose();

    expect(session.dispose, returnsNormally);
  });
}

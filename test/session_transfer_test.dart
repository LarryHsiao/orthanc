import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/session.dart';

void main() {
  /// Runs [transferPty] with fakes that log each call into [calls].
  Future<bool> run(
    List<String> calls, {
    Future<void> Function()? detach,
    Future<bool> Function()? send,
  }) => transferPty(
    detach: detach ?? () async => calls.add('detach'),
    send:
        send ??
        () async {
          calls.add('send');
          return true;
        },
    resume: () => calls.add('resume'),
    discard: () => calls.add('discard'),
  );

  test(
    'an accepted offer detaches, sends, discards and returns true',
    () async {
      final calls = <String>[];
      const expected = ['detach', 'send', 'discard'];

      final result = await run(calls);

      expect([result, calls], [true, expected]);
    },
  );

  test('a refused offer resumes and returns false, never discarding', () async {
    final calls = <String>[];
    const expected = ['detach', 'send', 'resume'];

    final result = await run(
      calls,
      send: () async {
        calls.add('send');
        return false;
      },
    );

    expect([result, calls], [false, expected]);
  });

  test('a send that throws resumes once and rethrows', () async {
    final calls = <String>[];
    const expected = ['detach', 'send', 'resume'];

    final outcome = run(
      calls,
      send: () async {
        calls.add('send');
        throw StateError('malloc failed');
      },
    );

    await expectLater(outcome, throwsStateError);
    expect(calls, expected);
  });

  test('a detach that throws resumes nothing and rethrows', () async {
    final calls = <String>[];
    const expected = <String>[];

    final outcome = run(
      calls,
      detach: () async => throw StateError('reentrant detach'),
    );

    await expectLater(outcome, throwsStateError);
    expect(calls, expected);
  });
}

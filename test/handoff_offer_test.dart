import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/handoff_offer.dart';

void main() {
  const sample = PaneOffer(
    manualName: 'scratch',
    name: 'zsh',
    activity: 'claude',
    executable: '/bin/zsh',
    pid: 4242,
    rows: 40,
    columns: 120,
  );

  test('round-trips every field through encode and decode', () {
    final result = decodePaneOffer(encodePaneOffer(sample));

    expect(result?.manualName, sample.manualName);
    expect(result?.name, sample.name);
    expect(result?.activity, sample.activity);
    expect(result?.executable, sample.executable);
    expect(result?.pid, sample.pid);
    expect(result?.rows, sample.rows);
    expect(result?.columns, sample.columns);
  });

  test('the wire body carries the current version under "v"', () {
    const expected = PaneOffer.currentVersion;

    final wire = jsonDecode(encodePaneOffer(sample)) as Map<String, dynamic>;

    expect(wire['v'], expected);
  });

  test('decoding malformed JSON returns null', () {
    const expected = null;

    final result = decodePaneOffer('{not valid json');

    expect(result, expected);
  });

  test('decoding a JSON value that is not an object returns null', () {
    const expected = null;

    final result = decodePaneOffer('[1, 2, 3]');

    expect(result, expected);
  });

  test('decoding a mismatched version returns null', () {
    const expected = null;

    final result = decodePaneOffer(
      '{"v": 999, "manualName": "", "name": "", "activity": "", '
      '"executable": "/bin/zsh", "pid": 1, "rows": 1, "columns": 1}',
    );

    expect(result, expected);
  });

  test('decoding a missing field returns null', () {
    const expected = null;

    final result = decodePaneOffer(
      '{"v": 1, "manualName": "", "name": "", "activity": "", '
      '"executable": "/bin/zsh", "pid": 1, "rows": 1}',
    );

    expect(result, expected);
  });

  test('decoding a wrong-typed field returns null', () {
    const expected = null;

    final result = decodePaneOffer(
      '{"v": 1, "manualName": "", "name": "", "activity": "", '
      '"executable": "/bin/zsh", "pid": "not a number", "rows": 1, '
      '"columns": 1}',
    );

    expect(result, expected);
  });
}

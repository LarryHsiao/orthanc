import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pane_title.dart';

void main() {
  test('shows activity alone when no name is set', () {
    const expected = 'check status';

    final result = paneTitle(name: '', activity: 'check status');

    expect(result, expected);
  });

  test('combines name and activity when both are set and differ', () {
    const expected = 'A — check status';

    final result = paneTitle(name: 'A', activity: 'check status');

    expect(result, expected);
  });

  test('shows activity alone when name equals activity', () {
    // The confirmed behavior of Claude Code's own OSC 0 title-setting
    // (see the spec's "Verified 2026-07-22" note): both notifiers fire from
    // the same event with the same string, so a naive combine would show
    // the value twice.
    const expected = '✳ Claude Code';

    final result = paneTitle(name: '✳ Claude Code', activity: '✳ Claude Code');

    expect(result, expected);
  });
}

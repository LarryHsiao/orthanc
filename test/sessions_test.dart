import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/sessions.dart';

void main() {
  test('gives each session a distinct id', () {
    final sessions = Sessions();

    final first = sessions.spawn();
    final second = sessions.spawn();

    expect(first.id, isNot(second.id));
  });

  test('finds a session by its id', () {
    final sessions = Sessions();

    final session = sessions.spawn();

    expect(sessions[session.id], same(session));
  });

  test('forgets a removed session', () {
    const expected = null;
    final sessions = Sessions();
    final session = sessions.spawn();

    sessions.remove(session.id);

    expect(sessions[session.id], expected);
  });
}

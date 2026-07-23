import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/sessions.dart';
import 'package:orthanc/settings.dart';

void main() {
  test('gives each session a distinct id', () {
    final sessions = Sessions(settings: ValueNotifier(const Settings()));

    final first = sessions.spawn();
    final second = sessions.spawn();

    expect(first.id, isNot(second.id));
  });

  test('finds a session by its id', () {
    final sessions = Sessions(settings: ValueNotifier(const Settings()));

    final session = sessions.spawn();

    expect(sessions[session.id], same(session));
  });

  test('forgets a removed session', () {
    const expected = null;
    final sessions = Sessions(settings: ValueNotifier(const Settings()));
    final session = sessions.spawn();

    sessions.remove(session.id);

    expect(sessions[session.id], expected);
  });

  test('spawns using the configured executable path when set', () {
    const expected = r'C:\custom\shell.exe';
    final sessions = Sessions(
      settings: ValueNotifier(const Settings(executablePath: expected)),
    );

    final session = sessions.spawn();

    expect(session.executable, expected);
  });
}

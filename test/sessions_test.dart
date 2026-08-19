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

  test('detach removes the session from the registry', () {
    const expected = null;
    final sessions = Sessions(settings: ValueNotifier(const Settings()));
    final session = sessions.spawn();

    sessions.detach(session.id);

    expect(sessions[session.id], expected);
  });

  test('detach returns the removed session', () {
    final sessions = Sessions(settings: ValueNotifier(const Settings()));
    final session = sessions.spawn();

    final detached = sessions.detach(session.id);

    expect(detached, same(session));
  });

  test('detach returns null for an id that was never spawned', () {
    const expected = null;
    final sessions = Sessions(settings: ValueNotifier(const Settings()));

    final detached = sessions.detach('missing');

    expect(detached, expected);
  });

  test('detach does not dispose the session, unlike remove', () {
    final sessions = Sessions(settings: ValueNotifier(const Settings()));
    final session = sessions.spawn();

    sessions.detach(session.id);

    // A disposed ValueNotifier throws FlutterError on addListener — the
    // one directly observable signal that dispose() never ran. remove()
    // would have disposed it and made this throw.
    expect(() => session.activity.addListener(() {}), returnsNormally);
    session.dispose();
  });

  test('spawns using the configured executable path when set', () {
    const expected = r'C:\custom\shell.exe';
    final sessions = Sessions(
      settings: ValueNotifier(const Settings(executablePath: expected)),
    );

    final session = sessions.spawn();

    expect(session.executable, expected);
  });

  test('adopt registers a session under a fresh id, findable by it', () {
    final sessions = Sessions(settings: ValueNotifier(const Settings()));

    final session = sessions.adopt(executable: '/bin/zsh');

    expect(sessions[session.id], same(session));
  });

  test('adopt uses the executable it is given, not the configured shell', () {
    const expected = '/bin/zsh';
    final sessions = Sessions(
      settings: ValueNotifier(const Settings(executablePath: '/usr/bin/fish')),
    );

    final session = sessions.adopt(executable: expected);

    expect(session.executable, expected);
  });

  test('adopt and spawn share the same id sequence, never colliding', () {
    final sessions = Sessions(settings: ValueNotifier(const Settings()));

    final spawned = sessions.spawn();
    final adopted = sessions.adopt(executable: '/bin/zsh');

    expect(spawned.id, isNot(adopted.id));
  });
}

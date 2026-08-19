import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session.dart';
import 'settings.dart';
import 'shell_command.dart';

/// The living sessions, by id.
///
/// The layout tree owns the arrangement; this owns the things arranged. Neither
/// knows about the other, which is what keeps the tree testable.
class Sessions {
  Sessions({required this.settings});

  final ValueNotifier<Settings> settings;

  final _byId = <String, Session>{};
  var _next = 0;

  /// Starts a session running the configured executable, or the detected
  /// shell when none is configured — the same command for every pane.
  Session spawn() => _register(
    shellCommand(
      isWindows: Platform.isWindows,
      environment: Platform.environment,
      configured: settings.value.executablePath,
    ),
  );

  /// Registers a session for a pane arriving from another window, without
  /// spawning anything — the caller wires its pty separately via
  /// [Session.adoptPty] once the transfer completes. [executable] comes
  /// from the sender's own offer, not this instance's configured shell:
  /// an adopted pane keeps running whatever program it already was.
  Session adopt({required String executable}) => _register(executable);

  Session _register(String executable) {
    final session = Session(id: '${_next++}', executable: executable);
    _byId[session.id] = session;
    return session;
  }

  Session? operator [](String id) => _byId[id];

  void remove(String id) {
    _byId.remove(id)?.dispose();
  }

  /// Removes [id] from the registry without disposing it — the session
  /// keeps running under whoever takes it over next, e.g. a pane handed
  /// off to another window. Unlike [remove], nothing about the session
  /// itself is torn down here; the caller now owns its whole lifecycle.
  Session? detach(String id) => _byId.remove(id);

  void disposeAll() {
    for (final session in _byId.values) {
      session.dispose();
    }
    _byId.clear();
  }
}

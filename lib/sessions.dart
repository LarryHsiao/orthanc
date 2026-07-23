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
  Session spawn() {
    final session = Session(
      id: '${_next++}',
      executable: shellCommand(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
        configured: settings.value.executablePath,
      ),
    );
    _byId[session.id] = session;
    return session;
  }

  Session? operator [](String id) => _byId[id];

  void remove(String id) {
    _byId.remove(id)?.dispose();
  }

  void disposeAll() {
    for (final session in _byId.values) {
      session.dispose();
    }
    _byId.clear();
  }
}

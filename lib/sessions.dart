import 'dart:io';

import 'session.dart';
import 'shell_command.dart';

/// The living sessions, by id.
///
/// The layout tree owns the arrangement; this owns the things arranged. Neither
/// knows about the other, which is what keeps the tree testable.
class Sessions {
  final _byId = <String, Session>{};
  var _next = 0;

  /// Starts a session running the same shell every pane runs.
  ///
  /// One command for every pane is deliberate: choosing a command per pane is
  /// deferred, and the user starts `claude` by hand inside the shell, exactly
  /// as they do today.
  Session spawn() {
    final session = Session(
      id: '${_next++}',
      executable: shellCommand(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
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

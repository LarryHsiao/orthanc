import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'pty_environment.dart';

/// How long a session goes without output before it is called idle.
///
/// There is no busy signal in a pty — nothing in the protocol says a program is
/// working. Output activity fits by accident of how TUIs work: an animating
/// spinner is continuous output, and a prompt waiting for input emits nothing.
/// Too short and the icon flickers between bursts; too long and it lags behind
/// a finished task. Only a running app settles the number.
const busyWindow = Duration(milliseconds: 500);

/// One running program, its terminal, and what the window needs to know of it.
///
/// A session outlives any widget: a pane that moves within the layout must not
/// restart its process. That is why the pty lives here rather than in a State,
/// as it did while the app held exactly one terminal for its whole life.
class Session {
  Session({required this.id, required this.executable});

  final String id;
  final String executable;

  final terminal = Terminal(maxLines: 10000);

  /// The title the running program sets for itself, via OSC 0/2 — the same one
  /// tmux and iTerm show. Claude Code writes its current task there.
  late final ValueNotifier<String> title = ValueNotifier(executable);

  /// Whether output has arrived within [busyWindow].
  final busy = ValueNotifier(false);

  Pty? _pty;
  Timer? _idleTimer;
  final _exited = Completer<int>();

  // kill() only requests termination; the pty's exitCode future resolves
  // later, once the OS actually reaps the process — which routinely
  // outlives dispose(). Guard every late callback (exit, output, idle
  // timer) against touching a ValueNotifier that dispose() already
  // disposed of.
  bool _disposed = false;

  Future<int> get exitCode => _exited.future;

  void start() {
    if (_pty != null) return;
    final pty = _spawn();
    _pty = pty;
    _wire(pty);
  }

  Pty _spawn() {
    // Without an explicit workingDirectory, Pty.start() defaults to wherever
    // this process's own cwd happens to be — unpredictable for a real
    // double-clicked .app, not just this dev session. Default to $HOME.
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return Pty.start(
      executable,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
      environment: ptyEnvironment(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
      ),
      workingDirectory: home,
    );
  }

  void _wire(Pty pty) {
    pty.output.cast<List<int>>().transform(const Utf8Decoder()).listen((data) {
      if (_disposed) return;
      terminal.write(data);
      _markBusy();
    });

    pty.exitCode.then(_handleExit);

    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (w, h, pw, ph) {
      pty.resize(h, w);
    };

    terminal.onTitleChange = (value) {
      if (value.isNotEmpty) title.value = value;
    };
  }

  void _markBusy() {
    busy.value = true;
    _idleTimer?.cancel();
    _idleTimer = Timer(busyWindow, () {
      if (!_disposed) busy.value = false;
    });
  }

  // Complete the exit future before touching anything disposal-sensitive, so
  // a caller awaiting exitCode is never left hanging by a late guard.
  void _handleExit(int code) {
    if (!_exited.isCompleted) _exited.complete(code);
    if (_disposed) return;
    terminal.write('the process exited with exit code $code');
    _idleTimer?.cancel();
    busy.value = false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _idleTimer?.cancel();
    _pty?.kill();
    title.dispose();
    busy.dispose();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'pty_environment.dart';

class PtyTerminal extends StatefulWidget {
  const PtyTerminal({
    super.key,
    required this.executable,
    this.arguments = const [],
    this.onExit,
  });

  final String executable;
  final List<String> arguments;

  /// Called with the spawned process's exit code once it ends.
  ///
  /// What that should mean is the app's to decide, not this widget's — quit,
  /// respawn, or show something in its place.
  final void Function(int exitCode)? onExit;

  @override
  State<PtyTerminal> createState() => _PtyTerminalState();
}

class _PtyTerminalState extends State<PtyTerminal> {
  final terminal = Terminal(maxLines: 10000);
  final terminalController = TerminalController();
  Pty? pty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (mounted) _startPty();
    });
  }

  void _startPty() {
    final ptyInstance = _spawn();
    pty = ptyInstance;
    _wire(ptyInstance);
  }

  Pty _spawn() {
    // Without an explicit workingDirectory, Pty.start() defaults to wherever
    // this process's own cwd happens to be — unpredictable for a real
    // double-clicked .app, not just this dev session. Default to $HOME.
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return Pty.start(
      widget.executable,
      arguments: widget.arguments,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
      environment: ptyEnvironment(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
      ),
      workingDirectory: home,
    );
  }

  void _wire(Pty ptyInstance) {
    ptyInstance.output
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen(terminal.write);

    ptyInstance.exitCode.then(_reportExit);

    terminal.onOutput = (data) {
      ptyInstance.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (w, h, pw, ph) {
      ptyInstance.resize(h, w);
    };
  }

  void _reportExit(int code) {
    // Feedback for a caller that lets the terminal outlive its process. When
    // onExit ends the app instead — as this app's does — no further frame is
    // painted and this line is never seen.
    terminal.write('the process exited with exit code $code');
    // Not when the widget is already going: dispose() kills the pty itself,
    // so closing the window would otherwise report that kill as the session
    // ending on its own. This reads the disposal as final teardown, which
    // holds while one PtyTerminal lives for the app's whole life; a caller
    // that disposes one mid-run — swapped on a route change, rebuilt under a
    // new key — would have a genuine exit swallowed here instead.
    if (mounted) widget.onExit?.call(code);
  }

  @override
  void dispose() {
    pty?.kill();
    terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      terminal,
      controller: terminalController,
      autofocus: true,
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class PtyTerminal extends StatefulWidget {
  const PtyTerminal({
    super.key,
    required this.executable,
    this.arguments = const [],
  });

  final String executable;
  final List<String> arguments;

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
    // flutter_pty only forwards a fixed allowlist of environment variables
    // (LOGNAME, USER, DISPLAY, LC_TYPE, HOME, PATH) to the spawned process,
    // and hardcodes TERM — COLORTERM is never passed through. Without it,
    // a truecolor-capable host still spawns a process that can't confirm
    // truecolor support to the spawned CLI, which may pick a more limited
    // color mode than it otherwise would.
    final colorterm = Platform.environment['COLORTERM'];
    // Without an explicit workingDirectory, Pty.start() defaults to wherever
    // this process's own cwd happens to be — unpredictable for a real
    // double-clicked .app, not just this dev session. Default to $HOME.
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    final ptyInstance = Pty.start(
      widget.executable,
      arguments: widget.arguments,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
      environment: colorterm != null ? {'COLORTERM': colorterm} : null,
      workingDirectory: home,
    );
    pty = ptyInstance;

    ptyInstance.output
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen(terminal.write);

    ptyInstance.exitCode.then((code) {
      terminal.write('the process exited with exit code $code');
    });

    terminal.onOutput = (data) {
      ptyInstance.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (w, h, pw, ph) {
      ptyInstance.resize(h, w);
    };
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

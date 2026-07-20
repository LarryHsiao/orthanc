import 'dart:io';

import 'package:flutter/material.dart';

import 'pty_terminal.dart';
import 'shell_command.dart';

void main() {
  runApp(const OrthancApp());
}

class OrthancApp extends StatelessWidget {
  const OrthancApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orthanc',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: PtyTerminal(
            executable: shellCommand(
              isWindows: Platform.isWindows,
              environment: Platform.environment,
            ),
            // The window exists to hold this one session; when the session
            // ends, so does the app, carrying the shell's own exit code out.
            onExit: exit,
          ),
        ),
      ),
    );
  }
}

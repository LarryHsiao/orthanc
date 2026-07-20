import 'dart:io';

import 'package:flutter/material.dart';

import 'claude_command.dart';
import 'pty_terminal.dart';

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
            executable: resolveClaudeCommand(
              home:
                  Platform.environment['HOME'] ??
                  Platform.environment['USERPROFILE'] ??
                  '',
              isWindows: Platform.isWindows,
              exists: (path) => File(path).existsSync(),
            ),
          ),
        ),
      ),
    );
  }
}

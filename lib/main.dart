import 'package:flutter/material.dart';

import 'workspace_view.dart';

void main() {
  runApp(const OrthancApp());
}

class OrthancApp extends StatelessWidget {
  const OrthancApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Orthanc',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: SafeArea(child: WorkspaceView())),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/shortcuts_dialog.dart';
import 'package:orthanc/shortcuts_reference.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showShortcutsDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every pane shortcut for the current platform', (
    tester,
  ) async {
    final expected = paneShortcuts(isWindows: Platform.isWindows);

    await pumpDialog(tester);

    expect(find.text('Keyboard Shortcuts'), findsOneWidget);
    for (final entry in expected) {
      expect(find.text(entry.label), findsOneWidget);
      expect(find.text(entry.keys), findsOneWidget);
    }
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Keyboard Shortcuts'), findsNothing);
  });
}

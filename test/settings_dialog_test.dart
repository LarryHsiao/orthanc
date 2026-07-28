import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/settings.dart';
import 'package:orthanc/settings_dialog.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'orthanc_settings_dialog_test',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<ValueNotifier<Settings>> pumpDialog(
    WidgetTester tester, {
    Settings initial = const Settings(),
    bool Function(String)? exists,
    String version = '1.1.4',
  }) async {
    final settings = ValueNotifier(initial);
    final file = File('${tempDir.path}/settings.json');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showSettingsDialog(
              context,
              settings: settings,
              file: file,
              exists: exists ?? (_) => true,
              detectedDefault: 'cmd.exe',
              version: version,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return settings;
  }

  testWidgets('field is prefilled with the current executablePath', (
    tester,
  ) async {
    const expected = r'C:\custom\shell.exe';

    await pumpDialog(tester, initial: const Settings(executablePath: expected));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, expected);
  });

  testWidgets('color scheme dropdown is prefilled with the current selection', (
    tester,
  ) async {
    const expected = TerminalColorScheme.dracula;

    await pumpDialog(tester, initial: const Settings(colorScheme: expected));

    final dropdown = tester.widget<DropdownButton<TerminalColorScheme>>(
      find.byType(DropdownButton<TerminalColorScheme>),
    );
    expect(dropdown.value, expected);
  });

  testWidgets('Save persists the picked color scheme', (tester) async {
    const expected = TerminalColorScheme.monokai;
    final settings = await pumpDialog(tester);

    await tester.tap(find.byType(DropdownButton<TerminalColorScheme>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monokai').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(settings.value.colorScheme, expected);
  });

  testWidgets('shows the app version', (tester) async {
    const expected = 'v1.1.4';

    await pumpDialog(tester, version: '1.1.4');

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('shows the detected default as placeholder text when unset', (
    tester,
  ) async {
    const expected = 'default: cmd.exe (detected)';

    await pumpDialog(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.hintText, expected);
  });

  testWidgets('typing a nonexistent path disables Save and shows an error', (
    tester,
  ) async {
    const expected = 'No file exists at this path — the old value is kept.';
    await pumpDialog(tester, exists: (_) => false);

    await tester.enterText(find.byType(TextField), r'C:\missing\shell.exe');
    await tester.pump();

    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Save'),
    );
    expect(save.onPressed, isNull);
    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('Save persists a valid path and updates settings', (
    tester,
  ) async {
    const expected = r'C:\custom\shell.exe';
    final settings = await pumpDialog(tester);

    await tester.enterText(find.byType(TextField), expected);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(settings.value.executablePath, expected);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Reset clears the field and is disabled when already empty', (
    tester,
  ) async {
    const expected = '';
    await pumpDialog(tester, initial: const Settings(executablePath: 'x'));

    await tester.tap(find.widgetWithText(TextButton, 'Reset to default'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, expected);
    final reset = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Reset to default'),
    );
    expect(reset.onPressed, isNull);
  });

  testWidgets('Cancel closes without persisting', (tester) async {
    const expected = null;
    final settings = await pumpDialog(tester);

    await tester.enterText(find.byType(TextField), r'C:\custom\shell.exe');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(settings.value.executablePath, expected);
    expect(find.byType(TextField), findsNothing);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';

import 'settings.dart';
import 'settings_store.dart';
import 'settings_validation.dart';

/// Opens the Settings dialog, letting the user override the executable each
/// new pane spawns.
Future<void> showSettingsDialog(
  BuildContext context, {
  required ValueNotifier<Settings> settings,
  required File file,
  required bool Function(String) exists,
  required String detectedDefault,
}) {
  return showDialog(
    context: context,
    builder: (_) => _SettingsDialog(
      settings: settings,
      file: file,
      exists: exists,
      detectedDefault: detectedDefault,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settings,
    required this.file,
    required this.exists,
    required this.detectedDefault,
  });

  final ValueNotifier<Settings> settings;
  final File file;
  final bool Function(String) exists;
  final String detectedDefault;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _controller = TextEditingController(
    text: widget.settings.value.executablePath ?? '',
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => executableExists(_controller.text, exists: widget.exists);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Startup executable path'),
            const SizedBox(height: 4),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'default: ${widget.detectedDefault} (detected)',
                errorText: _valid
                    ? null
                    : 'No file exists at this path — the old value is kept.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _controller.text.isEmpty ? null : _reset,
          child: const Text('Reset to default'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _valid ? _save : null, child: const Text('Save')),
      ],
    );
  }

  void _reset() => _controller.clear();

  void _save() {
    final updated = Settings(
      executablePath: normalizeExecutablePath(_controller.text),
    );
    widget.settings.value = updated;
    writeSettings(updated, file: widget.file);
    Navigator.pop(context);
  }
}

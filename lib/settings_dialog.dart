import 'dart:io';

import 'package:flutter/material.dart';

import 'settings.dart';
import 'settings_store.dart';
import 'settings_validation.dart';
import 'terminal_color_schemes.dart';
import 'terminal_font_families.dart';
import 'terminal_preview.dart';

/// Opens the Settings dialog, letting the user override the executable each
/// new pane spawns.
Future<void> showSettingsDialog(
  BuildContext context, {
  required ValueNotifier<Settings> settings,
  required File file,
  required bool Function(String) exists,
  required String detectedDefault,
  required String version,
}) {
  return showDialog(
    context: context,
    builder: (_) => _SettingsDialog(
      settings: settings,
      file: file,
      exists: exists,
      detectedDefault: detectedDefault,
      version: version,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.settings,
    required this.file,
    required this.exists,
    required this.detectedDefault,
    required this.version,
  });

  final ValueNotifier<Settings> settings;
  final File file;
  final bool Function(String) exists;
  final String detectedDefault;
  final String version;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _controller = TextEditingController(
    text: widget.settings.value.executablePath ?? '',
  );
  late var _colorScheme = widget.settings.value.colorScheme;
  late var _fontFamily = widget.settings.value.fontFamily;
  late var _fontSize = widget.settings.value.fontSize;

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

  double get _displayedFontSize => _fontSize ?? defaultTerminalFontSize;

  bool get _fontIsDefault =>
      _fontFamily == TerminalFontFamily.defaultFamily && _fontSize == null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
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
              const SizedBox(height: 16),
              const Text('Terminal color scheme'),
              const SizedBox(height: 4),
              DropdownButton<TerminalColorScheme>(
                value: _colorScheme,
                isExpanded: true,
                onChanged: (scheme) =>
                    setState(() => _colorScheme = scheme ?? _colorScheme),
                items: [
                  for (final scheme in TerminalColorScheme.values)
                    DropdownMenuItem(
                      value: scheme,
                      child: Text(terminalColorSchemeLabel(scheme)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Terminal font family'),
              const SizedBox(height: 4),
              DropdownButton<TerminalFontFamily>(
                value: _fontFamily,
                isExpanded: true,
                onChanged: (family) =>
                    setState(() => _fontFamily = family ?? _fontFamily),
                items: [
                  for (final family in TerminalFontFamily.values)
                    DropdownMenuItem(
                      value: family,
                      child: Text(terminalFontFamilyLabel(family)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Terminal font size'),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: _displayedFontSize <= minTerminalFontSize
                            ? null
                            : _decrementFontSize,
                      ),
                      Text('${_displayedFontSize.round()}'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _displayedFontSize >= maxTerminalFontSize
                            ? null
                            : _incrementFontSize,
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _fontIsDefault ? null : _resetFont,
                    child: const Text('Reset font'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TerminalPreview(
                scheme: _colorScheme,
                fontFamily: terminalFontFamilyName(_fontFamily),
                fontSize: _displayedFontSize,
              ),
              const SizedBox(height: 16),
              Text(
                'v${widget.version}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _controller.text.isEmpty ? null : _reset,
          child: const Text('Reset to default'),
        ),
        TextButton(
          onPressed: _colorScheme == TerminalColorScheme.defaultScheme
              ? null
              : _resetColorScheme,
          child: const Text('Reset scheme'),
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

  void _resetColorScheme() =>
      setState(() => _colorScheme = TerminalColorScheme.defaultScheme);

  void _incrementFontSize() =>
      setState(() => _fontSize = clampFontSize(_displayedFontSize + 1));

  void _decrementFontSize() =>
      setState(() => _fontSize = clampFontSize(_displayedFontSize - 1));

  void _resetFont() => setState(() {
    _fontFamily = TerminalFontFamily.defaultFamily;
    _fontSize = null;
  });

  void _save() {
    final updated = Settings(
      executablePath: normalizeExecutablePath(_controller.text),
      colorScheme: _colorScheme,
      fontFamily: _fontFamily,
      fontSize: _fontSize,
    );
    widget.settings.value = updated;
    writeSettings(updated, file: widget.file);
    Navigator.pop(context);
  }
}

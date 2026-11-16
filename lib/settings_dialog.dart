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
  required Future<void> Function(bool enabled) setLaunchAtLogin,
}) {
  return showDialog(
    context: context,
    builder: (_) => _SettingsDialog(
      settings: settings,
      file: file,
      exists: exists,
      detectedDefault: detectedDefault,
      version: version,
      setLaunchAtLogin: setLaunchAtLogin,
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
    required this.setLaunchAtLogin,
  });

  final ValueNotifier<Settings> settings;
  final File file;
  final bool Function(String) exists;
  final String detectedDefault;
  final String version;
  final Future<void> Function(bool enabled) setLaunchAtLogin;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  static const _executablePathFieldKey = Key('executablePathField');
  static const _historyLinesFieldKey = Key('historyLinesField');
  static const _neverFieldKey = Key('linkPreviewNeverField');
  static const _onlyFieldKey = Key('linkPreviewOnlyField');

  late final _controller = TextEditingController(
    text: widget.settings.value.executablePath ?? '',
  );
  late final _historyLinesController = TextEditingController(
    text: '${widget.settings.value.historyLines}',
  );
  late final _neverController = TextEditingController(
    text: widget.settings.value.linkPreviewNever.join('\n'),
  );
  late final _onlyController = TextEditingController(
    text: widget.settings.value.linkPreviewOnly.join('\n'),
  );
  late var _linkPreviewEnabled = widget.settings.value.linkPreviewEnabled;
  late var _colorScheme = widget.settings.value.colorScheme;
  late var _fontFamily = widget.settings.value.fontFamily;
  late var _fontSize = widget.settings.value.fontSize;
  late var _startQuakeAtLogin = widget.settings.value.startQuakeAtLogin;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _historyLinesController.addListener(() => setState(() {}));
    _neverController.addListener(() => setState(() {}));
    _onlyController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _historyLinesController.dispose();
    _neverController.dispose();
    _onlyController.dispose();
    super.dispose();
  }

  bool get _valid => executableExists(_controller.text, exists: widget.exists);

  int? get _historyLines => parseHistoryLines(_historyLinesController.text);

  // Patterns are checked only while link preview is on: a hand-edited bad
  // pattern in a switched-off, uneditable field must not lock Save.
  PatternError? get _neverError =>
      _linkPreviewEnabled ? firstPatternError(_neverController.text) : null;

  PatternError? get _onlyError =>
      _linkPreviewEnabled ? firstPatternError(_onlyController.text) : null;

  bool get _canSave =>
      _valid &&
      _historyLines != null &&
      _neverError == null &&
      _onlyError == null;

  double get _displayedFontSize =>
      clampFontSize(_fontSize ?? defaultTerminalFontSize).roundToDouble();

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
                key: _executablePathFieldKey,
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'default: ${widget.detectedDefault} (detected)',
                  errorText: _valid
                      ? null
                      : 'No file exists at this path — the old value is kept.',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Scrollback history (lines)'),
              const SizedBox(height: 4),
              TextField(
                key: _historyLinesFieldKey,
                controller: _historyLinesController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'default: $defaultHistoryLines',
                  errorText: _historyLines != null
                      ? null
                      : 'Enter a whole number between $minHistoryLines and '
                            '$maxHistoryLines.',
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
              const Text('Terminal font'),
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
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _startQuakeAtLogin,
                onChanged: (checked) =>
                    setState(() => _startQuakeAtLogin = checked ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Start quake mode at login'),
              ),
              const Divider(height: 24),
              ..._linkPreviewSection(context),
              const SizedBox(height: 8),
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
        TextButton(
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
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

  List<Widget> _linkPreviewSection(BuildContext context) {
    final caption = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.grey);
    return [
      CheckboxListTile(
        value: _linkPreviewEnabled,
        onChanged: (checked) =>
            setState(() => _linkPreviewEnabled = checked ?? false),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Preview links on hover'),
      ),
      Text(
        'Hovering a link fetches the page, so the site sees your IP.',
        style: caption,
      ),
      const SizedBox(height: 16),
      ..._patternField(
        label: 'Never preview (regex, one per line)',
        fieldKey: _neverFieldKey,
        controller: _neverController,
        error: _neverError,
        hint: defaultLinkPreviewNever.first,
      ),
      const SizedBox(height: 16),
      ..._patternField(
        label: 'Only preview (regex, one per line)',
        fieldKey: _onlyFieldKey,
        controller: _onlyController,
        error: _onlyError,
        hint: 'empty = any link not excluded',
      ),
      const SizedBox(height: 4),
      Text(
        'An empty "Only" list means any link not excluded above. '
        '"Never" wins over "Only".',
        style: caption,
      ),
    ];
  }

  List<Widget> _patternField({
    required String label,
    required Key fieldKey,
    required TextEditingController controller,
    required PatternError? error,
    required String hint,
  }) {
    return [
      Text(label),
      const SizedBox(height: 4),
      TextField(
        key: fieldKey,
        controller: controller,
        enabled: _linkPreviewEnabled,
        // Regex is read character by character, so it gets the terminal's
        // monospace face rather than the dialog's proportional one.
        style: const TextStyle(
          fontFamily: defaultTerminalFontFamily,
          fontFamilyFallback: terminalFontFamilyFallback,
        ),
        keyboardType: TextInputType.multiline,
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: hint,
          errorMaxLines: 3,
          errorText: error == null
              ? null
              : 'Line ${error.line}: invalid pattern — ${error.reason}.',
        ),
      ),
    ];
  }

  void _save() {
    final updated = Settings(
      executablePath: normalizeExecutablePath(_controller.text),
      colorScheme: _colorScheme,
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      startQuakeAtLogin: _startQuakeAtLogin,
      historyLines: _historyLines!,
      linkPreviewEnabled: _linkPreviewEnabled,
      linkPreviewNever: patternLinesFromText(_neverController.text),
      linkPreviewOnly: patternLinesFromText(_onlyController.text),
    );
    if (_startQuakeAtLogin != widget.settings.value.startQuakeAtLogin) {
      widget.setLaunchAtLogin(_startQuakeAtLogin);
    }
    widget.settings.value = updated;
    writeSettings(updated, file: widget.file);
    Navigator.pop(context);
  }
}

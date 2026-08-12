import 'dart:io';

import 'package:flutter/material.dart';

import 'shortcuts_reference.dart';

/// Opens the Keyboard Shortcuts dialog, a read-only reference for every pane
/// hotkey — the labels shown match the current platform.
Future<void> showShortcutsDialog(BuildContext context) {
  return showDialog(context: context, builder: (_) => const _ShortcutsDialog());
}

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    final entries = paneShortcuts(isWindows: Platform.isWindows);
    return AlertDialog(
      title: const Text('Keyboard Shortcuts'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.label),
                      Text(
                        entry.keys,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

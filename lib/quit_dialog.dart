import 'package:flutter/material.dart';

/// Confirms before the app quits — shown for the "Quit" menu item and its
/// ⌘Q shortcut alike, since a `PlatformMenuItem`'s `onSelected` fires for
/// either trigger the same way. Resolves `true` if the user chose to quit.
Future<bool> showQuitDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Quit Orthanc?'),
      content: const Text('Every running session in this window will end.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Quit'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

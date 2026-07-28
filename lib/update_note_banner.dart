import 'package:flutter/material.dart';

/// A one-time, non-blocking note that Orthanc updated itself since the last
/// launch. Purely informational — it never intercepts keyboard input, so it
/// must not sit in the focus chain the terminal panes rely on.
class UpdateNoteBanner extends StatelessWidget {
  const UpdateNoteBanner({
    super.key,
    required this.version,
    required this.onDismiss,
  });

  final String version;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blueGrey.shade800,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Updated to v$version',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 16),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

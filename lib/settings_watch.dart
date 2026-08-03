import 'dart:io';

import 'package:flutter/foundation.dart';

import 'settings.dart';
import 'settings_store.dart';

/// Returns [next] only when it differs from [current]; otherwise returns
/// [current] unchanged, so a caller can skip a needless [ValueNotifier]
/// update (and the rebuild it would trigger) on a no-op file event.
///
/// [Settings] carries no `==` override, so this compares its fields
/// directly rather than relying on identity equality.
Settings reconcileSettings({
  required Settings current,
  required Settings next,
}) {
  final changed =
      current.executablePath != next.executablePath ||
      current.colorScheme != next.colorScheme ||
      current.fontFamily != next.fontFamily ||
      current.fontSize != next.fontSize;
  return changed ? next : current;
}

/// Keeps [settings] in sync with [file] on disk: whenever another window's
/// save changes it, this window's panes see the new value without needing
/// to be reopened. A stream error (or a read landing mid atomic-rename) is
/// swallowed — the next filesystem event, or this window's own next
/// launch, resyncs state.
///
/// [writeSettings]'s atomic rename-over-existing-file surfaces differently
/// per platform: watching for [FileSystemEvent.modify] alone is enough on
/// macOS, but on Windows the replace reports on the destination path as a
/// [FileSystemEvent.delete] (the pre-existing file being replaced), so that
/// must be watched too for the reload to fire there.
void watchSettingsFile({
  required File file,
  required ValueNotifier<Settings> settings,
}) {
  file.parent
      .watch(events: FileSystemEvent.modify | FileSystemEvent.delete)
      .where((event) => event.path == file.path)
      .listen((_) {
        if (!file.existsSync()) return;
        settings.value = reconcileSettings(
          current: settings.value,
          next: readSettings(file: file),
        );
      }, onError: (_) {});
}

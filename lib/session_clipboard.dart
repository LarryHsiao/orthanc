import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

import 'pasted_file_paths.dart';
import 'session.dart';
import 'session_drop.dart';

/// Copies [session]'s current selection to the clipboard. Selection survives
/// a copy — matching xterm's own CopySelectionTextIntent handler, which
/// never clears it either. A no-op with nothing selected.
void copySelection(Session session) {
  final selection = session.terminalController.selection;
  if (selection == null) return;
  final text = session.terminal.buffer.getText(selection);
  Clipboard.setData(ClipboardData(text: text));
}

/// Pastes the clipboard's contents into [session]'s terminal and clears its
/// selection. A file on the clipboard wins over text — see
/// [pastedFilePaths] for why a copied web link doesn't get mistaken for one
/// — and is written exactly as [dropPathsInto] writes a drop, since the two
/// gestures land in the same place: a path, in whichever form the pane's
/// own state calls for. Next, raw image bytes with no file behind them —
/// what LINE, a browser, or a screenshot tool leave on the clipboard — are
/// written to a temp PNG and handed to [dropPathsInto] the same way; this
/// is the case [pastedFilePaths] cannot catch, since there was never a path
/// to find. Only when neither survives does this fall back to a plain text
/// paste, unchanged from before this file read the clipboard's file
/// contents at all. A no-op when the clipboard holds none of the three.
///
/// [readFiles] and [fileExists] are injected only for tests — real callers
/// pass neither, and the defaults ([Pasteboard.files], [File.existsSync])
/// are the only implementation that ever ships. Likewise [readImage] and
/// [writeImageFile] default to [Pasteboard.image] and a real temp-file
/// write. [isWindows] is threaded through to [dropPathsInto], matching its
/// own convention of reading `Platform.isWindows` once, at the real I/O
/// boundary, rather than inside code meant to stay testable.
Future<void> pasteIntoSession(
  Session session, {
  required bool isWindows,
  Future<List<String>> Function()? readFiles,
  bool Function(String)? fileExists,
  Future<Uint8List?> Function()? readImage,
  String Function(Uint8List)? writeImageFile,
}) async {
  final files = pastedFilePaths(
    await (readFiles ?? Pasteboard.files)(),
    exists: fileExists ?? (path) => File(path).existsSync(),
  );
  if (files.isNotEmpty) {
    dropPathsInto(session, files, isWindows: isWindows);
    return;
  }
  final image = await (readImage ?? () => Pasteboard.image)();
  if (image != null && image.isNotEmpty) {
    final path = (writeImageFile ?? _writePastedImage)(image);
    dropPathsInto(session, [path], isWindows: isWindows);
    return;
  }
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text == null || text.isEmpty) return;
  session.terminal.paste(text);
  session.terminalController.clearSelection();
}

/// Writes a pasted clipboard image to a fresh file under the system temp
/// directory and returns its path. `Pasteboard.image` returns PNG bytes on
/// every platform it supports, so the extension is fixed rather than
/// sniffed. The timestamp in the filename is enough to keep repeated pastes
/// in one session from colliding; nothing here ever deletes the file — the
/// pane that reads it (typically Claude Code, via the `@`-reference
/// [dropPathsInto] writes) owns it from here on, the same lifetime a
/// dropped or clipboard-copied file already has.
String _writePastedImage(Uint8List bytes) {
  final path = p.join(
    Directory.systemTemp.path,
    'orthanc-paste-${DateTime.now().microsecondsSinceEpoch}.png',
  );
  File(path).writeAsBytesSync(bytes);
  return path;
}

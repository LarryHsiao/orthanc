import 'package:flutter/services.dart';

import 'session.dart';

/// Copies [session]'s current selection to the clipboard. Selection survives
/// a copy — matching xterm's own CopySelectionTextIntent handler, which
/// never clears it either. A no-op with nothing selected.
void copySelection(Session session) {
  final selection = session.terminalController.selection;
  if (selection == null) return;
  final text = session.terminal.buffer.getText(selection);
  Clipboard.setData(ClipboardData(text: text));
}

/// Pastes the clipboard's text into [session]'s terminal and clears its
/// selection. A no-op when the clipboard holds no text.
Future<void> pasteIntoSession(Session session) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text == null || text.isEmpty) return;
  session.terminal.paste(text);
  session.terminalController.clearSelection();
}

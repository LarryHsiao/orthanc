import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'layout_node.dart';
import 'session.dart';
import 'sessions.dart';
import 'split_shortcuts.dart';
import 'split_view.dart';
import 'workspace.dart';

/// The window: the sessions, their arrangement, and the keys that change it.
class WorkspaceView extends StatefulWidget {
  const WorkspaceView({super.key});

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  final sessions = Sessions();
  late Workspace workspace;

  // kill() (called by Sessions.remove(), via Session.dispose()) only
  // requests termination — exitCode's future, and thus the listener
  // registered in _open() below, complete later, once the OS reaps the
  // process. That completion routinely lands after _close() has already
  // handled the same id once. Track ids already closed so the late arrival
  // is a no-op rather than a second close of a pane already gone.
  final _closed = <String>{};

  @override
  void initState() {
    super.initState();
    // First run opens one session — there is no empty state to design.
    final first = _open();
    workspace = Workspace.single(first.id);
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (mounted) first.start();
    });
  }

  Session _open() {
    final session = sessions.spawn();
    session.exitCode.then((code) {
      if (mounted) _close(session.id, exitCode: code);
    });
    return session;
  }

  /// A finished session closes its own pane; the last one quits the app,
  /// carrying the shell's exit code out as it did when the window held one.
  /// A close by hotkey has no process exit code yet, so it keeps using 0.
  void _close(String id, {int exitCode = 0}) {
    if (!_closed.add(id)) return;

    final next = workspace.close(id);
    if (next == null) {
      sessions.disposeAll();
      exit(exitCode);
    }
    sessions.remove(id);
    setState(() => workspace = next);
    _requestFocus(next.focusedId);
  }

  void _split(SplitAxis axis) {
    final session = _open();
    setState(() {
      workspace = workspace.split(axis: axis, newSessionId: session.id);
    });
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (!mounted) return;
      session.start();
      session.focusNode.requestFocus();
    });
  }

  void _moveFocus(Direction direction) {
    final target = workspace.neighbour(direction);
    if (target == null) return;
    setState(() => workspace = workspace.focus(target));
    _requestFocus(target);
  }

  void _onPaneFocus(String id) {
    setState(() => workspace = workspace.focus(id));
    _requestFocus(id);
  }

  /// Moves keyboard focus onto [id]'s session.
  ///
  /// `autofocus` is honoured only once, when a node first registers into a
  /// scope holding no other focus — a rebuild with a new focused id does
  /// nothing on its own, so every focus change must request it explicitly.
  /// Deferred to end of frame: a newly split session's node is not attached
  /// until its TerminalView has been built.
  void _requestFocus(String id) {
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (mounted) sessions[id]?.focusNode.requestFocus();
    });
  }

  /// Steals a key before the terminal can have it, or lets it through.
  ///
  /// In a terminal app every keystroke belongs to the terminal, so a binding
  /// that is not taken here lands in the running program's prompt instead.
  /// Passed to every TerminalView as `onKeyEvent`, which xterm consults
  /// before its own shortcut keytab and before writing to the pty — the
  /// ancestor [Focus] below only backstops the moment no terminal holds
  /// focus at all.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final action = _paneActionFor(event);
    if (action == null) return KeyEventResult.ignored;

    // A held hotkey streams KeyRepeatEvents; re-firing split/close on every
    // one would cascade panes into existence or out of it. The repeat is
    // still swallowed here rather than falling through to the pty, but it
    // triggers no second action.
    if (event is! KeyRepeatEvent) _dispatch(action);
    return KeyEventResult.handled;
  }

  PaneAction? _paneActionFor(KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    return paneAction(
      isWindows: Platform.isWindows,
      key: event.logicalKey,
      isControlPressed: keys.isControlPressed,
      isShiftPressed: keys.isShiftPressed,
      isAltPressed: keys.isAltPressed,
      isMetaPressed: keys.isMetaPressed,
    );
  }

  void _dispatch(PaneAction action) {
    switch (action) {
      case SplitPane(:final axis):
        _split(axis);
      case ClosePane():
        _close(workspace.focusedId);
      case MoveFocus(:final direction):
        _moveFocus(direction);
    }
  }

  @override
  void dispose() {
    sessions.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKey,
      child: SplitView(
        node: workspace.root,
        sessions: sessions,
        focusedId: workspace.focusedId,
        onFocus: _onPaneFocus,
        onKeyEvent: _onKey,
        onResize: (split, index, delta) => setState(() {
          workspace = workspace.resizeSplit(
            split: split,
            dividerIndex: index,
            delta: delta,
          );
        }),
      ),
    );
  }
}

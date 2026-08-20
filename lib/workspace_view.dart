import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';

import 'handoff_endpoint.dart';
import 'handoff_offer.dart';
import 'layout_node.dart';
import 'new_instance.dart';
import 'session.dart';
import 'sessions.dart';
import 'settings.dart';
import 'settings_validation.dart';
import 'split_shortcuts.dart';
import 'split_view.dart';
import 'terminal_color_schemes.dart';
import 'terminal_font_families.dart';
import 'workspace.dart';

/// The pane under whole-window fractional coordinates [fx]/[fy] — the same
/// 0..1 space [Workspace.paneRects] speaks — paired with the drop zone
/// within its own rect, or null when the point falls outside every pane
/// (the divider gutter, or off the tree entirely).
///
/// The pure half of what a drag's pointer position resolves to: turning a
/// raw global [Offset] into this fractional space needs a real rendered
/// box, so that conversion stays in [_WorkspaceViewState]
/// (`_fractionalPosition`); everything past that point — which pane, which
/// zone — does not, and lives here so it is testable with no widget tree.
({String id, Direction? side})? dropTargetAt(
  Workspace workspace,
  double fx,
  double fy,
) {
  for (final entry in workspace.paneRects().entries) {
    final rect = entry.value;
    if (fx >= rect.left &&
        fx <= rect.right &&
        fy >= rect.top &&
        fy <= rect.bottom) {
      return (id: entry.key, side: rect.zoneAt(fx, fy));
    }
  }
  return null;
}

/// A liveness probe for [liveHandoffEndpoints] — `SIGCONT` is the closest
/// substitute `dart:io` exposes for a bare POSIX `kill(pid, 0)`: delivered,
/// it is a no-op for a normally-running process, and [Process.killPid]
/// reports whether the target existed to receive it at all.
bool _isProcessAlive(int pid) => Process.killPid(pid, ProcessSignal.sigcont);

/// The window: the sessions, their arrangement, and the keys that change it.
class WorkspaceView extends StatefulWidget {
  const WorkspaceView({
    super.key,
    required this.settings,
    required this.onEmpty,
    required this.supportDir,
    required this.paneOffers,
  });

  final ValueNotifier<Settings> settings;

  /// Called once the last pane closes, with the exit code of whichever
  /// session closed it (0 for a close by hotkey, which has no process exit
  /// code yet). What "empty" means is the caller's call: an ordinary window
  /// exits the process; the quake window hides itself instead, and this
  /// widget reopens a fresh session either way once [onEmpty] returns — an
  /// [exit] call never returns, so that reopening is unreachable for an
  /// ordinary window, exactly as today.
  final void Function(int exitCode) onEmpty;

  /// Where this instance's own outgoing handoffs are addressed from, and
  /// where a sender looks to find this instance at all — see
  /// `handoff_endpoint.dart`.
  final Directory supportDir;

  /// Panes arriving from another window, one [PtyOffer] per drag —
  /// `main()`'s single [Pty.listen] call for this process's whole life.
  final Stream<PtyOffer> paneOffers;

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  late final sessions = Sessions(settings: widget.settings);
  late Workspace workspace;
  final _boundsKey = GlobalKey();
  String? _dragSourceId;
  String? _dragHoverId;
  Direction? _dragHoverSide;

  // kill() (called by Sessions.remove(), via Session.dispose()) only
  // requests termination — exitCode's future, and thus the listener
  // registered in _open() below, complete later, once the OS reaps the
  // process. That completion routinely lands after _close() has already
  // handled the same id once. Track ids already closed so the late arrival
  // is a no-op rather than a second close of a pane already gone.
  final _closed = <String>{};

  StreamSubscription<PtyOffer>? _offerSubscription;

  @override
  void initState() {
    super.initState();
    // First run opens one session — there is no empty state to design.
    final first = _open();
    workspace = Workspace.single(first.id);
    _requestFocus(first.id, before: first.start);
    _offerSubscription = widget.paneOffers.listen(_handleOffer);
  }

  /// Answers a pane offered by another window. Rejects outright — never
  /// reaching [Pty.accept] — for anything that doesn't decode as exactly
  /// [PaneOffer.currentVersion]'s shape, or if this widget is no longer
  /// mounted to place it. Otherwise accepts immediately (the sender's own
  /// [Pty.send] only needs to know ownership was taken, not that every
  /// last bit of session/tree wiring below has finished), lands beside
  /// [Workspace.focusedId] — the "dumb" discovery this step deliberately
  /// ships with, real drop-point geometry is later work — and wires the
  /// pty in via the same end-of-frame [_requestFocus] seam [Session.start]
  /// already uses, so it runs only once the new pane's `TerminalView` has
  /// laid out and can report its real geometry.
  void _handleOffer(PtyOffer offer) {
    final metadata = decodePaneOffer(
      utf8.decode(offer.metadata, allowMalformed: true),
    );
    if (metadata == null || !mounted) {
      Pty.offerReply(offer, false);
      return;
    }

    final Pty pty;
    try {
      pty = Pty.accept(offer, pid: metadata.pid);
    } on StateError {
      Pty.offerReply(offer, false);
      return;
    }
    Pty.offerReply(offer, true);

    final session = sessions.adopt(executable: metadata.executable);
    _watchExit(session);
    session.manualName.value = metadata.manualName;
    session.name.value = metadata.name;
    session.activity.value = metadata.activity;

    setState(() {
      workspace = workspace.insert(
        newSessionId: session.id,
        targetId: workspace.focusedId,
      );
    });
    _requestFocus(session.id, before: () => session.adoptPty(pty));
  }

  Session _open() {
    final session = sessions.spawn();
    _watchExit(session);
    return session;
  }

  /// Closes [session]'s own pane once its process exits on its own —
  /// registered for every session this window comes to hold, however it
  /// arrived: freshly spawned ([_open]) or adopted from a handoff
  /// ([_handleOffer]). Easy to forget for the latter, since adoption has
  /// no other reason to reach into [WorkspaceView] at all — the pty's own
  /// exit signal is already correctly wired regardless (see
  /// [Session.adoptPty]/`_wire`), only *this* window's reaction to it is
  /// each session's own responsibility to ask for.
  void _watchExit(Session session) {
    session.exitCode.then((code) {
      if (mounted) _close(session.id, exitCode: code);
    });
  }

  /// A finished session closes its own pane; the last one empties this
  /// window. What that means is [WorkspaceView.onEmpty]'s call — an ordinary
  /// window exits the process directly, carrying the shell's exit code out
  /// as its own and leaving any other window standing, untouched; the quake
  /// window hides itself instead and is reopened fresh right here, since
  /// [onEmpty] returns rather than terminating the process. A close by
  /// hotkey has no process exit code yet, so it keeps using 0.
  void _close(String id, {int exitCode = 0}) {
    if (!_closed.add(id)) return;
    _finishRemoval(id, exitCode: exitCode);
  }

  /// The shared tail of a pane leaving this window's tree and registry,
  /// for good — whether it died ([_close]) or departed alive to another
  /// window ([_attemptCrossInstanceHandoff]). Callers are responsible for
  /// their own claim on [_closed] *before* calling this: [_close] claims
  /// it itself; [_attemptCrossInstanceHandoff] must already hold it by the
  /// time a handoff is confirmed accepted, since [sessions.remove] here is
  /// safe to call on a departed session only because its pty is already
  /// gone by then — see [Session.handOffTo].
  void _finishRemoval(String id, {int exitCode = 0}) {
    final next = workspace.close(id);
    if (next == null) {
      sessions.disposeAll();
      widget.onEmpty(exitCode);
      _reopen();
      return;
    }
    // Claims focus before the departing session's node is disposed, so
    // primary focus never passes through the root scope — a key pressed in
    // that gap would otherwise be dropped entirely (see _onKey's doc).
    sessions[next.focusedId]?.focusNode.requestFocus();
    sessions.remove(id);
    setState(() => workspace = next);
    _requestFocus(next.focusedId);
  }

  /// Opens a fresh session in a fresh single-pane workspace — what
  /// [initState] does for the very first pane, and what an empty window
  /// [onEmpty] declined to end the process over does again.
  void _reopen() {
    final first = _open();
    setState(() => workspace = Workspace.single(first.id));
    _requestFocus(first.id, before: first.start);
  }

  void _split(SplitAxis axis) {
    final session = _open();
    setState(() {
      workspace = workspace.split(axis: axis, newSessionId: session.id);
    });
    _requestFocus(session.id, before: session.start);
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

  void _toggleCollapse(String id) {
    setState(() => workspace = workspace.toggleCollapse(id));
    _requestFocus(id);
  }

  void _expand(String id) {
    setState(() => workspace = workspace.toggleExpand(id));
    _requestFocus(id);
  }

  void _onDragStart(String id) {
    setState(() => _dragSourceId = id);
  }

  void _onDragUpdate(String id, Offset globalPosition) {
    final fraction = _fractionalPosition(globalPosition);
    final hit = fraction == null
        ? null
        : dropTargetAt(workspace, fraction.dx, fraction.dy);
    final next = (hit != null && hit.id != id) ? hit.id : null;
    final side = next == null ? null : hit!.side;
    if (next == _dragHoverId && side == _dragHoverSide) return;
    setState(() {
      _dragHoverId = next;
      _dragHoverSide = side;
    });
  }

  /// Converts [globalPosition] into the same 0..1 fractional space
  /// [Workspace.paneRects] speaks, through [_boundsKey]'s own rendered
  /// box — or null before that box has ever been laid out.
  Offset? _fractionalPosition(Offset globalPosition) {
    final box = _boundsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return null;
    final local = box.globalToLocal(globalPosition);
    return Offset(local.dx / box.size.width, local.dy / box.size.height);
  }

  void _onDragEnd(String id) {
    final target = _dragHoverId;
    final side = _dragHoverSide;
    setState(() {
      _dragSourceId = null;
      _dragHoverId = null;
      _dragHoverSide = null;
      if (target != null) {
        workspace = side == null
            ? workspace.swap(id, target)
            : workspace.move(sourceId: id, targetId: target, side: side);
      }
    });
    // A drop with no in-tree target means the pointer left this window
    // entirely — the one existing case (the divider gutter, or off the
    // tree) and the new one (another instance's window) share this same
    // signal; only a real handoff attempt tells them apart.
    if (target == null) unawaited(_attemptCrossInstanceHandoff(id));
  }

  /// Tries to hand [id]'s pane to another running instance, when a drag
  /// ends outside this window's own tree. The "dumb" discovery this step
  /// ships with: the first other live instance found, landing beside its
  /// own `focusedId` — real drop-point geometry is separate, later work.
  ///
  /// A no-op on Windows (see [crossInstanceHandoffSupported]) — the drag
  /// simply cancels, same as dropping on the divider gutter.
  ///
  /// Claims [_closed] for [id] *before* any `await`, for the whole
  /// in-flight window: [Session.handOffTo]'s own doc warns that
  /// discarding or killing a pty racing its own in-flight send is unsafe,
  /// and an ordinary hotkey close reaching this same id mid-attempt would
  /// do exactly that. Every early return releases the claim again; only a
  /// confirmed acceptance keeps it, feeding into [_finishRemoval] (which
  /// never re-claims it — the claim already made is what it relies on).
  Future<void> _attemptCrossInstanceHandoff(String id) async {
    if (!crossInstanceHandoffSupported(isWindows: Platform.isWindows)) {
      return;
    }
    if (!_closed.add(id)) return;

    final session = sessions[id];
    final childPid = session?.pid;
    if (session == null || childPid == null) {
      _closed.remove(id);
      return;
    }

    final endpoints = liveHandoffEndpoints(
      supportDir: widget.supportDir,
      ownPid: pid,
      isAlive: _isProcessAlive,
    );
    if (endpoints.isEmpty) {
      _closed.remove(id); // nobody else running — pane stays exactly put
      return;
    }
    final target = endpoints.first;

    final metadata = utf8.encode(
      encodePaneOffer(
        PaneOffer(
          manualName: session.manualName.value,
          name: session.name.value,
          activity: session.activity.value,
          executable: session.executable,
          pid: childPid,
          rows: session.terminal.viewHeight,
          columns: session.terminal.viewWidth,
        ),
      ),
    );

    bool accepted;
    try {
      accepted = await session.handOffTo(
        target.file.path,
        metadata: metadata,
        targetPid: target.pid,
      );
    } catch (_) {
      // handOffTo can throw uncaught if detach() itself fails (e.g. a
      // reentrant call) — treated the same as an ordinary rejection
      // rather than left to escape unhandled from a fire-and-forget call.
      accepted = false;
    }

    if (!mounted) return;
    if (!accepted) {
      _closed.remove(id); // rejected, or the send itself failed — the
      // pane already resumed inside handOffTo; nothing here changed.
      return;
    }
    _finishRemoval(id);
  }

  /// Moves keyboard focus onto [id]'s session, once end of frame arrives.
  ///
  /// `autofocus` is honoured only once, when a node first registers into a
  /// scope holding no other focus — a rebuild with a new focused id does
  /// nothing on its own, so every focus change must request it explicitly.
  /// Deferred to end of frame: a session's node is not attached until its
  /// TerminalView has been built — true of a freshly split pane and of the
  /// very first pane at startup alike. [before] runs first, inside the same
  /// deferral, for callers that also need to start the session.
  void _requestFocus(String id, {VoidCallback? before}) {
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (!mounted) return;
      before?.call();
      sessions[id]?.focusNode.requestFocus();
    });
  }

  /// Steals a key before the terminal can have it, or lets it through.
  ///
  /// In a terminal app every keystroke belongs to the terminal, so a binding
  /// that is not taken here lands in the running program's prompt instead.
  /// Passed to every TerminalView as `onKeyEvent`, which xterm consults
  /// before its own shortcut keytab and before writing to the pty. The
  /// ancestor [Focus] in [build] runs this same handler, but Flutter
  /// dispatches a key to the primary-focus node and walks upward from
  /// there — so that ancestor `Focus` is reached only while some terminal
  /// holds primary focus, which is the one case needing no backstop. When
  /// no terminal holds focus, primary focus rests on the root scope, of
  /// which this widget is a descendant rather than an ancestor, and the
  /// key never reaches either handler. That window is instead closed by
  /// requesting focus onto a session's node whenever `focusedId` changes
  /// (see [_requestFocus]) — not by this widget.
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
      case ToggleCollapse():
        _toggleCollapse(workspace.focusedId);
      case NewWindow():
        startNewInstance();
    }
  }

  @override
  void dispose() {
    _offerSubscription?.cancel();
    sessions.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Settings>(
      valueListenable: widget.settings,
      builder: (context, settings, _) {
        return Focus(
          // Re-runs _onKey for keys a terminal returns `ignored` on; see
          // _onKey's doc for why this is not a backstop for the no-focus
          // case.
          onKeyEvent: _onKey,
          child: Container(
            key: _boundsKey,
            child: SplitView(
              node: workspace.root,
              sessions: sessions,
              focusedId: workspace.focusedId,
              highlightFocus: workspace.isSplit,
              collapsedIds: workspace.collapsedIds,
              collapsibleIds: workspace.collapsibleIds,
              theme: terminalThemeFor(settings.colorScheme),
              fontFamily: terminalFontFamilyName(settings.fontFamily),
              fontSize: clampFontSize(
                settings.fontSize ?? defaultTerminalFontSize,
              ),
              onFocus: _onPaneFocus,
              onKeyEvent: _onKey,
              onToggleCollapse: _toggleCollapse,
              onExpand: _expand,
              onResize: (split, index, delta) => setState(() {
                workspace = workspace.resizeSplit(
                  split: split,
                  dividerIndex: index,
                  delta: delta,
                );
              }),
              // Unlike highlightFocus above, drag is never gated on
              // isSplit: a lone pane is exactly the case someone will want
              // to fling into another window (cross-instance handoff) even
              // though there is nothing to swap or move it with in-tree.
              canDrag: true,
              onDragStart: _onDragStart,
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
              dragSourceId: _dragSourceId,
              dragHoverId: _dragHoverId,
              dragHoverSide: _dragHoverSide,
            ),
          ),
        );
      },
    );
  }
}

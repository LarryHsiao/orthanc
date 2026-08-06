import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'home_directory.dart';
import 'pty_environment.dart';
import 'shell_prompt_hook.dart';

/// One running program, its terminal, and what the window needs to know of it.
///
/// A session outlives any widget: a pane that moves within the layout must not
/// restart its process. That is why the pty lives here rather than in a State,
/// as it did while the app held exactly one terminal for its whole life.
class Session {
  Session({required this.id, required this.executable}) {
    activity.addListener(_onActivityChanged);
    focusNode.addListener(_onFocusChanged);
  }

  final String id;
  final String executable;

  final terminal = Terminal(maxLines: 10000);

  /// This pane's keyboard focus, held here rather than in a widget: a pane
  /// that moves within the tree, or loses and regains the focused id, must
  /// not lose or recreate its focus node — the same reason [terminal] lives
  /// here rather than in a State.
  late final focusNode = FocusNode(debugLabel: 'session $id');

  /// What the running program is doing right now, via OSC 2 ("window
  /// title") — Claude Code's current task while it runs, or the shell's own
  /// prompt hook announcing its pwd once idle (see shell_prompt_hook.dart).
  late final ValueNotifier<String> activity = ValueNotifier(executable);

  /// The session's own name, via OSC 1 ("icon name") — set only when the
  /// running program renames itself; empty until then.
  late final ValueNotifier<String> name = ValueNotifier('');

  /// A name the user sets directly, via [PaneBar]'s rename control —
  /// independent of anything the running program sets. See
  /// docs/superpowers/specs/2026-07-23-orthanc-pane-rename-design.md.
  late final ValueNotifier<String> manualName = ValueNotifier('');

  /// Whether this pane finished a burst of [activity] changes while
  /// unfocused and has not been looked at since — [PaneBar] marks it with a
  /// stripe until [focusNode] gains focus. Driven purely by how often
  /// [activity] changes, never by what it says: Claude Code's title updates
  /// roughly once a second while it works and stops the instant a turn
  /// completes, so a burst followed by [_quietThreshold] of silence is a
  /// reliable "done" signal without reading program-set text for meaning —
  /// consistent with docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md's
  /// "the title comes from the program, not from us".
  late final ValueNotifier<bool> needsAttention = ValueNotifier(false);

  // A single change (e.g. the shell prompt hook's own idle-pwd reset) must
  // never arm the signal on its own, or an idle pane would flag itself the
  // first time its title happens to be set. Arming needs two changes inside
  // _burstWindow of each other — real, ongoing activity, not one reset.
  static const _burstWindow = Duration(milliseconds: 1500);
  static const _quietThreshold = Duration(seconds: 2);
  DateTime? _lastActivityChangeAt;
  bool _armed = false;
  Timer? _quietTimer;

  void _onActivityChanged() {
    final now = clock.now();
    final last = _lastActivityChangeAt;
    _lastActivityChangeAt = now;
    if (last != null && now.difference(last) <= _burstWindow) {
      _armed = true;
    }
    _quietTimer?.cancel();
    if (_armed) {
      _quietTimer = Timer(_quietThreshold, _onQuiet);
    }
  }

  void _onQuiet() {
    _armed = false;
    if (!focusNode.hasFocus) needsAttention.value = true;
  }

  void _onFocusChanged() {
    if (focusNode.hasFocus) needsAttention.value = false;
  }

  Pty? _pty;
  final _exited = Completer<int>();

  // kill() only requests termination; the pty's exitCode future resolves
  // later, once the OS actually reaps the process — which routinely
  // outlives dispose(). Guard every late callback (exit, output) against
  // touching a ValueNotifier that dispose() already disposed of.
  bool _disposed = false;

  // Set once _handleExit runs, so dispose() knows the OS has already reaped
  // this pid — killing it again could hit an unrelated process the OS has
  // since recycled onto the same pid.
  bool _processExited = false;

  Future<int> get exitCode => _exited.future;

  void start() {
    if (_pty != null) return;
    final pty = _spawn();
    _pty = pty;
    _wire(pty);
  }

  Pty _spawn() {
    // Without an explicit workingDirectory, Pty.start() defaults to wherever
    // this process's own cwd happens to be — unpredictable for a real
    // double-clicked .app, not just this dev session. Default to the user's
    // home, which is not the same variable on every platform: see
    // homeDirectory().
    final home = homeDirectory(
      isWindows: Platform.isWindows,
      environment: Platform.environment,
    );
    final hook = shellPromptHook(
      isWindows: Platform.isWindows,
      executable: executable,
      environment: Platform.environment,
    );
    final env = ptyEnvironment(
      isWindows: Platform.isWindows,
      environment: Platform.environment,
    );
    return Pty.start(
      executable,
      arguments: hook.arguments,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
      environment: {...env, ...hook.environment},
      workingDirectory: home,
    );
  }

  void _wire(Pty pty) {
    pty.output.cast<List<int>>().transform(const Utf8Decoder()).listen((data) {
      if (_disposed) return;
      terminal.write(data);
    });

    pty.exitCode.then(_handleExit);

    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (w, h, pw, ph) {
      pty.resize(h, w);
    };

    terminal.onTitleChange = (value) {
      if (value.isNotEmpty) activity.value = value;
    };

    terminal.onIconChange = (value) {
      if (value.isNotEmpty) name.value = value;
    };
  }

  // Complete the exit future before touching anything disposal-sensitive, so
  // a caller awaiting exitCode is never left hanging by a late guard.
  void _handleExit(int code) {
    _processExited = true;
    if (!_exited.isCompleted) _exited.complete(code);
    if (_disposed) return;
    terminal.write('the process exited with exit code $code');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_processExited) _pty?.kill();
    _quietTimer?.cancel();
    activity.removeListener(_onActivityChanged);
    focusNode.removeListener(_onFocusChanged);
    focusNode.dispose();
    activity.dispose();
    name.dispose();
    manualName.dispose();
    needsAttention.dispose();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_root.dart';
import 'handoff_endpoint.dart';
import 'home_directory.dart';
import 'launch_at_login.dart';
import 'new_instance.dart';
import 'quake_geometry_store.dart';
import 'quake_lock.dart';
import 'quake_summon.dart';
import 'quake_window.dart';
import 'quit_dialog.dart';
import 'settings.dart';
import 'settings_dialog.dart';
import 'settings_store.dart';
import 'settings_watch.dart';
import 'shell_command.dart';
import 'shortcuts_dialog.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final file = settingsFile(supportDir: supportDir);
  final settings = ValueNotifier(readSettings(file: file));
  watchSettingsFile(file: file, settings: settings);
  final kind = instanceKind(arguments: args);

  // A quake instance claims the lock before anything else — before the
  // channel exists, before any window shows. Losing means another quake
  // instance already runs: summon it instead, and go no further.
  RandomAccessFile? quakeLock;
  if (kind == InstanceKind.quake) {
    quakeLock = acquireQuakeLock(file: quakeLockFile(supportDir: supportDir));
    if (quakeLock == null) {
      requestQuakeSummon(file: quakeSummonFile(supportDir: supportDir));
      exit(0);
    }
  }

  // One listener per process, for as long as it runs — a pane arriving
  // from another window via drag can land at any point in this instance's
  // life, not just at startup. Every instance kind (first, secondary,
  // quake) is an equally valid destination.
  //
  // Guarded: a native/Dart version mismatch in the handoff plugin (e.g. an
  // installed build whose flutter_pty.dll predates the Dart bindings it's
  // called with) must never take the whole window down with it — it did,
  // once, when this call threw before runApp() ever ran. Falling back to an
  // empty stream just means this instance never receives a handed-off pane.
  Stream<PtyOffer> paneOffers;
  try {
    paneOffers = Pty.listen(
      handoffEndpointFile(supportDir: supportDir, pid: pid).path,
    );
  } catch (error, stackTrace) {
    debugPrint(
      'Pty.listen failed, handoff receiving disabled: $error\n$stackTrace',
    );
    paneOffers = const Stream<PtyOffer>.empty();
  }

  runApp(
    OrthancApp(
      settings: settings,
      settingsFile: file,
      kind: kind,
      supportDir: supportDir,
      quakeLock: quakeLock,
      paneOffers: paneOffers,
    ),
  );
}

class OrthancApp extends StatefulWidget {
  const OrthancApp({
    super.key,
    required this.settings,
    required this.settingsFile,
    required this.kind,
    required this.supportDir,
    required this.paneOffers,
    this.quakeLock,
  });

  final ValueNotifier<Settings> settings;
  final File settingsFile;
  final InstanceKind kind;
  final Directory supportDir;

  /// Panes arriving from another window — forwarded to [WorkspaceView] via
  /// [AppRoot]. See `main()`: one [Pty.listen] call per process, for this
  /// process's whole life.
  final Stream<PtyOffer> paneOffers;

  /// Held open for as long as this process runs, when [kind] is
  /// [InstanceKind.quake] — see `main()`. Closed in [State.dispose].
  final RandomAccessFile? quakeLock;

  @override
  State<OrthancApp> createState() => _OrthancAppState();
}

class _OrthancAppState extends State<OrthancApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const _systemMenuChannel = MethodChannel('orthanc/system_menu');
  QuakeWindow? _quakeWindow;
  StreamSubscription<FileSystemEvent>? _summonSubscription;

  @override
  void initState() {
    super.initState();
    // Windows has no Flutter menu bar: its runner hangs a "Settings…" item off
    // the window's own system menu and calls in over this channel
    // (windows/runner/flutter_window.cpp). macOS reaches the same dialog
    // through the PlatformMenuItem below instead.
    _systemMenuChannel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') _openSettings();
      if (call.method == 'openShortcuts') _openShortcuts();
      if (call.method == 'openQuake') _summonOrSpawnQuake();
    });
    if (widget.kind == InstanceKind.quake) {
      _quakeWindow = QuakeWindow(
        geometryFile: quakeGeometryFile(supportDir: widget.supportDir),
      );
      _quakeWindow!.registerHotKey();
      _quakeWindow!.reveal();
      _summonSubscription = watchQuakeSummon(
        file: quakeSummonFile(supportDir: widget.supportDir),
        onSummon: () => _quakeWindow?.reveal(),
      );
    }
  }

  @override
  void dispose() {
    final quakeLock = widget.quakeLock;
    if (quakeLock != null) releaseQuakeLock(quakeLock);
    _summonSubscription?.cancel();
    super.dispose();
  }

  Future<void> _openSettings() async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showSettingsDialog(
      context,
      settings: widget.settings,
      file: widget.settingsFile,
      exists: (path) => File(path).existsSync(),
      detectedDefault: shellCommand(
        isWindows: Platform.isWindows,
        environment: Platform.environment,
      ),
      version: info.version,
      setLaunchAtLogin: (enabled) => const LaunchAtLogin().setEnabled(
        enabled,
        isWindows: Platform.isWindows,
        isMacOS: Platform.isMacOS,
        homeDir: homeDirectory(
          isWindows: Platform.isWindows,
          environment: Platform.environment,
        ),
        bundleId: info.packageName,
        resolvedExecutable: Platform.resolvedExecutable,
      ),
    );
  }

  void _openShortcuts() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showShortcutsDialog(context);
  }

  /// Asked for by the "Quit" menu item and its ⌘Q shortcut alike. `exit`
  /// closes every file descriptor, including the quake lock's — see
  /// `quake_lock.dart` — so no extra cleanup is owed here.
  Future<void> _confirmQuit() async {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final confirmed = await showQuitDialog(context);
    if (confirmed) exit(0);
  }

  /// What an emptied window means: an ordinary window exits the process; the
  /// quake window hides instead, so it can be reopened by the next summon.
  void _onEmpty(int exitCode) {
    if (widget.kind == InstanceKind.quake) {
      _quakeWindow?.hide();
    } else {
      exit(exitCode);
    }
  }

  /// Asked for by the "Quake Window" menu item on either platform. Probes
  /// the lock a running quake instance would hold: if it is free, no quake
  /// instance runs yet, so this spawns one; if it is held, one already
  /// runs, so this asks it to show itself instead of spawning a duplicate.
  Future<void> _summonOrSpawnQuake() async {
    final lock = acquireQuakeLock(
      file: quakeLockFile(supportDir: widget.supportDir),
    );
    if (lock == null) {
      requestQuakeSummon(file: quakeSummonFile(supportDir: widget.supportDir));
      return;
    }
    releaseQuakeLock(lock);
    await startNewInstance(kind: InstanceKind.quake);
  }

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Orthanc',
          menus: [
            PlatformMenuItem(
              label: 'New Window',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: startNewInstance,
            ),
            PlatformMenuItem(
              label: 'Quake Window',
              onSelected: _summonOrSpawnQuake,
            ),
            PlatformMenuItem(
              label: 'Settings…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: _openSettings,
            ),
            PlatformMenuItem(
              label: 'Keyboard Shortcuts…',
              onSelected: _openShortcuts,
            ),
            PlatformMenuItem(
              label: 'Quit',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyQ,
                meta: true,
              ),
              onSelected: _confirmQuit,
            ),
          ],
        ),
      ],
      // macOS treats ⌘Q as reserved: a plain PlatformMenuItem's key
      // equivalent for it is silently dropped, even though the same item's
      // native menu click fires `onSelected` correctly. This mirrors
      // WorkspaceView's own ancestor `Focus(onKeyEvent: ...)` — the proven
      // way a shortcut here still fires while a terminal pane holds focus.
      // The menu item above keeps its own (currently inert) ⌘Q shortcut
      // only to render the hint text; if a future Flutter/macOS release
      // makes that binding fire too, this would double-dispatch on one
      // press — worth remembering if a double dialog is ever reported.
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyQ, meta: true):
              _confirmQuit,
        },
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Orthanc',
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(
              child: AppRoot(
                settings: widget.settings,
                isFirstInstance: widget.kind == InstanceKind.first,
                onEmpty: _onEmpty,
                supportDir: widget.supportDir,
                paneOffers: widget.paneOffers,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

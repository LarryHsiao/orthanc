import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_root.dart';
import 'new_instance.dart';
import 'quake_lock.dart';
import 'quake_summon.dart';
import 'quake_window.dart';
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

  runApp(
    OrthancApp(
      settings: settings,
      settingsFile: file,
      kind: kind,
      supportDir: supportDir,
      quakeLock: quakeLock,
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
    this.quakeLock,
  });

  final ValueNotifier<Settings> settings;
  final File settingsFile;
  final InstanceKind kind;
  final Directory supportDir;

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
      _quakeWindow = QuakeWindow();
      _quakeWindow!.registerHotKey();
      _quakeWindow!.show();
      _summonSubscription = watchQuakeSummon(
        file: quakeSummonFile(supportDir: widget.supportDir),
        onSummon: () => _quakeWindow?.show(),
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
    );
  }

  void _openShortcuts() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showShortcutsDialog(context);
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
          ],
        ),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Orthanc',
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: AppRoot(
              settings: widget.settings,
              isFirstInstance: widget.kind == InstanceKind.first,
            ),
          ),
        ),
      ),
    );
  }
}

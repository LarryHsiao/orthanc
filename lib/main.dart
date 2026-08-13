import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_root.dart';
import 'new_instance.dart';
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
  runApp(OrthancApp(settings: settings, settingsFile: file, kind: kind));
}

class OrthancApp extends StatefulWidget {
  const OrthancApp({
    super.key,
    required this.settings,
    required this.settingsFile,
    required this.kind,
  });

  final ValueNotifier<Settings> settings;
  final File settingsFile;
  final InstanceKind kind;

  @override
  State<OrthancApp> createState() => _OrthancAppState();
}

class _OrthancAppState extends State<OrthancApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const _systemMenuChannel = MethodChannel('orthanc/system_menu');

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
      if (call.method == 'openQuake') _openQuake();
    });
    if (widget.kind == InstanceKind.quake) {
      final quakeWindow = QuakeWindow();
      quakeWindow.registerHotKey();
      quakeWindow.show();
    }
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

  void _openQuake() {
    startNewInstance(kind: InstanceKind.quake);
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
              onSelected: () => startNewInstance(kind: InstanceKind.quake),
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

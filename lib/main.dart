import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_root.dart';
import 'settings.dart';
import 'settings_dialog.dart';
import 'settings_store.dart';
import 'settings_watch.dart';
import 'shell_command.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDir = await getApplicationSupportDirectory();
  final file = settingsFile(supportDir: supportDir);
  final settings = ValueNotifier(readSettings(file: file));
  watchSettingsFile(file: file, settings: settings);
  runApp(OrthancApp(settings: settings, settingsFile: file));
}

class OrthancApp extends StatefulWidget {
  const OrthancApp({
    super.key,
    required this.settings,
    required this.settingsFile,
  });

  final ValueNotifier<Settings> settings;
  final File settingsFile;

  @override
  State<OrthancApp> createState() => _OrthancAppState();
}

class _OrthancAppState extends State<OrthancApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const _systemMenuChannel = MethodChannel('orthanc/system_menu');

  @override
  void initState() {
    super.initState();
    _systemMenuChannel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') _openSettings();
    });
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

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Orthanc',
          menus: [
            PlatformMenuItem(
              label: 'Settings…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: _openSettings,
            ),
          ],
        ),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Orthanc',
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(child: AppRoot(settings: widget.settings)),
        ),
      ),
    );
  }
}

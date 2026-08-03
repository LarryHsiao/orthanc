import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';
import 'update_note.dart';
import 'update_note_banner.dart';
import 'workspace_view.dart';

const _lastSeenVersionKey = 'last_seen_version';
const _appcastFeedUrl =
    'https://raw.githubusercontent.com/LarryHsiao/orthanc/master/appcast.xml';

/// Hosts the workspace, and around it: a silent launch-time update check
/// (Sparkle/WinSparkle, via [autoUpdater]) and a one-time note if the last
/// check already landed one. Both are best-effort — neither may ever block
/// the terminal from opening or stand between the user and their keyboard.
class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.settings,
    required this.isPrimaryWindow,
  });

  final ValueNotifier<Settings> settings;
  final bool isPrimaryWindow;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  UpdateNoteState? _note;

  @override
  void initState() {
    super.initState();
    if (widget.isPrimaryWindow) {
      _showUpdateNoteIfAny();
      _checkForUpdate();
    }
  }

  Future<void> _showUpdateNoteIfAny() async {
    final info = await PackageInfo.fromPlatform();
    final prefs = await SharedPreferences.getInstance();
    final state = await updateNoteOnLaunch(
      readLastSeenVersion: () async => prefs.getString(_lastSeenVersionKey),
      writeLastSeenVersion: (version) =>
          prefs.setString(_lastSeenVersionKey, version),
      currentVersion: info.version,
    );
    if (state.shouldShow && mounted) {
      setState(() => _note = state);
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      await autoUpdater.setFeedURL(_appcastFeedUrl);
      await autoUpdater.checkForUpdates(inBackground: true);
    } catch (_) {
      // Fail silent by design — see the design spec's Error handling
      // section. A missing feed or a network hiccup is not worth
      // surfacing at launch; the next launch tries again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    return Column(
      children: [
        if (note != null)
          UpdateNoteBanner(
            version: note.version,
            onDismiss: () => setState(() => _note = null),
          ),
        Expanded(child: WorkspaceView(settings: widget.settings)),
      ],
    );
  }
}

import 'dart:io';

import 'package:flutter/services.dart';

import 'new_instance.dart';

/// The path to this app's quake-mode launchd agent, under [homeDir] —
/// `~/Library/LaunchAgents/<bundleId>.quake.plist`. launchd scans this
/// directory automatically at every login once the file is present, so
/// dropping or removing it is the whole of the registration.
File macOSLaunchAgentFile({required String homeDir, required String bundleId}) {
  return File('$homeDir/Library/LaunchAgents/$bundleId.quake.plist');
}

/// The launchd agent plist that starts quake mode at login. `RunAtLoad`
/// fires [arguments] once, every time launchd loads the agent — which
/// happens automatically at each login once [macOSLaunchAgentFile] exists.
String macOSLaunchAgentPlist({
  required String bundleId,
  required String executable,
  required List<String> arguments,
}) {
  final programArguments = [
    executable,
    ...arguments,
  ].map((value) => '    <string>${_escapeXml(value)}</string>').join('\n');
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0">\n'
      '<dict>\n'
      '  <key>Label</key>\n'
      '  <string>$bundleId.quake</string>\n'
      '  <key>ProgramArguments</key>\n'
      '  <array>\n'
      '$programArguments\n'
      '  </array>\n'
      '  <key>RunAtLoad</key>\n'
      '  <true/>\n'
      '</dict>\n'
      '</plist>\n';
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Registers or unregisters this app as a login item so quake mode can start
/// automatically at PC launch. Dart decides; each platform carries out its
/// own concrete registration:
///
/// * Windows: native writes/removes the `Run` registry value — see
///   `windows/runner/flutter_window.cpp`.
/// * macOS: a launchd agent plist under `~/Library/LaunchAgents`, whose
///   `ProgramArguments` rerun the same `open -n -a <bundle> --args quake`
///   command [newInstanceCommand] already uses to spawn a fresh quake
///   instance — see there for why `open` is used rather than the raw
///   executable. [homeDir], [bundleId] and [resolvedExecutable] are the
///   caller's to resolve (`Platform.environment['HOME']`,
///   `PackageInfo.packageName`, `Platform.resolvedExecutable`) — a missing
///   one is treated as "can't register" and is a no-op rather than a crash.
class LaunchAtLogin {
  const LaunchAtLogin()
    : _channel = const MethodChannel('orthanc/launch_at_login');

  final MethodChannel _channel;

  Future<void> setEnabled(
    bool enabled, {
    required bool isWindows,
    required bool isMacOS,
    String? homeDir,
    String? bundleId,
    String? resolvedExecutable,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runProcess,
  }) async {
    if (isWindows) {
      await _channel.invokeMethod('setEnabled', {'enabled': enabled});
      return;
    }
    if (!isMacOS ||
        homeDir == null ||
        bundleId == null ||
        resolvedExecutable == null) {
      return;
    }
    final run = runProcess ?? Process.run;
    final file = macOSLaunchAgentFile(homeDir: homeDir, bundleId: bundleId);
    if (enabled) {
      final command = newInstanceCommand(
        isMacOS: true,
        resolvedExecutable: resolvedExecutable,
        kind: InstanceKind.quake,
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        macOSLaunchAgentPlist(
          bundleId: bundleId,
          executable: command.executable,
          arguments: command.arguments,
        ),
      );
      await run('launchctl', ['load', '-w', file.path]);
    } else {
      await run('launchctl', ['unload', '-w', file.path]);
      if (file.existsSync()) file.deleteSync();
    }
  }
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/launch_at_login.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('macOSLaunchAgentFile', () {
    test('names the plist under Library/LaunchAgents', () {
      const expected =
          '/Users/tester/Library/LaunchAgents/com.example.orthanc.quake.plist';

      final result = macOSLaunchAgentFile(
        homeDir: '/Users/tester',
        bundleId: 'com.example.orthanc',
      );

      expect(result.path, expected);
    });
  });

  group('macOSLaunchAgentPlist', () {
    test('carries the label, program arguments, and RunAtLoad', () {
      const expected =
          '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
          '<plist version="1.0">\n'
          '<dict>\n'
          '  <key>Label</key>\n'
          '  <string>com.example.orthanc.quake</string>\n'
          '  <key>ProgramArguments</key>\n'
          '  <array>\n'
          '    <string>/usr/bin/open</string>\n'
          '    <string>-n</string>\n'
          '    <string>-a</string>\n'
          '    <string>/Applications/Orthanc.app</string>\n'
          '    <string>--args</string>\n'
          '    <string>quake</string>\n'
          '  </array>\n'
          '  <key>RunAtLoad</key>\n'
          '  <true/>\n'
          '</dict>\n'
          '</plist>\n';

      final result = macOSLaunchAgentPlist(
        bundleId: 'com.example.orthanc',
        executable: '/usr/bin/open',
        arguments: const [
          '-n',
          '-a',
          '/Applications/Orthanc.app',
          '--args',
          'quake',
        ],
      );

      expect(result, expected);
    });

    test('escapes XML-significant characters in an argument', () {
      const expected = '    <string>&amp;&lt;&gt;</string>';

      final result = macOSLaunchAgentPlist(
        bundleId: 'com.example.orthanc',
        executable: '&<>',
        arguments: const [],
      );

      expect(result, contains(expected));
    });
  });

  group('setEnabled on Windows', () {
    const channel = MethodChannel('orthanc/launch_at_login');
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('setEnabled(true) asks native to register the login item', () async {
      const expected = MethodCall('setEnabled', {'enabled': true});

      await const LaunchAtLogin().setEnabled(
        true,
        isWindows: true,
        isMacOS: false,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, expected.method);
      expect(calls.single.arguments, expected.arguments);
    });

    test(
      'setEnabled(false) asks native to unregister the login item',
      () async {
        const expected = MethodCall('setEnabled', {'enabled': false});

        await const LaunchAtLogin().setEnabled(
          false,
          isWindows: true,
          isMacOS: false,
        );

        expect(calls, hasLength(1));
        expect(calls.single.method, expected.method);
        expect(calls.single.arguments, expected.arguments);
      },
    );
  });

  group('setEnabled on macOS', () {
    late Directory tempDir;
    late List<List<Object?>> processCalls;

    Future<ProcessResult> fakeRunProcess(
      String executable,
      List<String> arguments,
    ) async {
      processCalls.add([executable, arguments]);
      return ProcessResult(0, 0, '', '');
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'orthanc_launch_at_login_test',
      );
      processCalls = [];
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('setEnabled(true) writes the plist and loads it', () async {
      const expectedProcessCall = [
        'launchctl',
        ['load', '-w'],
      ];

      await const LaunchAtLogin().setEnabled(
        true,
        isWindows: false,
        isMacOS: true,
        homeDir: tempDir.path,
        bundleId: 'com.example.orthanc',
        resolvedExecutable: '/Applications/Orthanc.app/Contents/MacOS/orthanc',
        runProcess: fakeRunProcess,
      );

      final file = macOSLaunchAgentFile(
        homeDir: tempDir.path,
        bundleId: 'com.example.orthanc',
      );
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('/Applications/Orthanc.app'));
      expect(file.readAsStringSync(), contains('quake'));
      expect(processCalls, hasLength(1));
      expect(processCalls.single[0], expectedProcessCall[0]);
      expect(processCalls.single[1], contains('load'));
      expect(processCalls.single[1], contains('-w'));
    });

    test('setEnabled(false) unloads and removes the plist', () async {
      const expected = false;
      final file = macOSLaunchAgentFile(
        homeDir: tempDir.path,
        bundleId: 'com.example.orthanc',
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('placeholder');

      await const LaunchAtLogin().setEnabled(
        false,
        isWindows: false,
        isMacOS: true,
        homeDir: tempDir.path,
        bundleId: 'com.example.orthanc',
        resolvedExecutable: '/Applications/Orthanc.app/Contents/MacOS/orthanc',
        runProcess: fakeRunProcess,
      );

      expect(file.existsSync(), expected);
      expect(processCalls, hasLength(1));
      expect(processCalls.single[1], contains('unload'));
    });

    test('setEnabled is a no-op when isMacOS is false', () async {
      const expected = <List<Object?>>[];

      await const LaunchAtLogin().setEnabled(
        true,
        isWindows: false,
        isMacOS: false,
        homeDir: tempDir.path,
        bundleId: 'com.example.orthanc',
        resolvedExecutable: '/Applications/Orthanc.app/Contents/MacOS/orthanc',
        runProcess: fakeRunProcess,
      );

      expect(processCalls, expected);
    });

    test(
      'setEnabled is a no-op on macOS when a required detail is missing',
      () async {
        const expected = <List<Object?>>[];

        await const LaunchAtLogin().setEnabled(
          true,
          isWindows: false,
          isMacOS: true,
          bundleId: 'com.example.orthanc',
          resolvedExecutable:
              '/Applications/Orthanc.app/Contents/MacOS/orthanc',
          runProcess: fakeRunProcess,
        );

        expect(processCalls, expected);
      },
    );
  });
}

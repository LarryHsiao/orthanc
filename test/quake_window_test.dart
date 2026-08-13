import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/quake_geometry_store.dart';
import 'package:orthanc/quake_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('orthanc/quake');
  const codec = StandardMethodCodec();

  // Simulates native forwarding a hotkey press to Dart. Waits for the reply
  // callback rather than a fixed delay, so it only resolves once
  // QuakeWindow's own handling — including a reveal's currentScreen/show
  // round trip — has actually finished.
  Future<void> sendToggle({required bool visible}) {
    final data = codec.encodeMethodCall(
      MethodCall('toggle', {'visible': visible}),
    );
    final completer = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, data, (_) => completer.complete());
    return completer.future;
  }

  // Simulates native reporting the end of a user's resize drag.
  Future<void> sendResized({required double width, required double height}) {
    final data = codec.encodeMethodCall(
      MethodCall('resized', {'width': width, 'height': height}),
    );
    final completer = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, data, (_) => completer.complete());
    return completer.future;
  }

  late Directory tempDir;
  late List<MethodCall> calls;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('orthanc_quake_window_test');
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'currentScreen') {
            return {'x': 0.0, 'y': 0.0, 'width': 1920.0, 'height': 1080.0};
          }
          return null;
        });
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  QuakeWindow buildWindow() =>
      QuakeWindow(geometryFile: File('${tempDir.path}/quake_geometry.json'));

  test('registerHotKey asks native to claim the hotkey', () async {
    await buildWindow().registerHotKey();

    final expected = 'registerHotKey';
    expect(calls.single.method, expected);
  });

  test('hide asks native to conceal the window', () async {
    await buildWindow().hide();

    final expected = 'hide';
    expect(calls.single.method, expected);
  });

  test('reveal asks native for the current screen, then shows there', () async {
    await buildWindow().reveal();

    final expected = ['currentScreen', 'show'];
    expect(calls.map((call) => call.method).toList(), expected);
  });

  test('reveal computes a snapped frame from the reported screen', () async {
    await buildWindow().reveal();

    final args = calls.last.arguments as Map;
    final expectedWidth = 1920.0;
    final expectedHeight = 540.0;
    expect(args['width'], expectedWidth);
    expect(args['height'], expectedHeight);
  });

  test('a toggle while visible asks native to hide', () async {
    buildWindow();
    await sendToggle(visible: true);

    final expected = 'hide';
    expect(calls.single.method, expected);
  });

  test('a toggle while hidden reveals via the current screen', () async {
    buildWindow();
    await sendToggle(visible: false);

    final expected = ['currentScreen', 'show'];
    expect(calls.map((call) => call.method).toList(), expected);
  });

  test('a resize notification persists the new size', () async {
    final window = buildWindow();

    await sendResized(width: 1000.0, height: 450.0);

    final expected = (width: 1000.0, height: 450.0);
    expect(readQuakeGeometry(file: window.geometryFile), expected);
  });

  test('a subsequent reveal honors the persisted resize', () async {
    final window = buildWindow();
    await sendResized(width: 1000.0, height: 450.0);
    calls.clear();

    await window.reveal();

    final args = calls.last.arguments as Map;
    final expectedWidth = 1000.0;
    final expectedHeight = 450.0;
    expect(args['width'], expectedWidth);
    expect(args['height'], expectedHeight);
  });
}

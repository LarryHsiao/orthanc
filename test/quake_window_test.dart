import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/quake_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('orthanc/quake');
  const codec = StandardMethodCodec();

  // Simulates native forwarding a hotkey press to Dart. Waits for the
  // reply callback rather than a fixed delay, so it only resolves once
  // QuakeWindow's own handling has actually finished.
  Future<void> sendToggle({required bool visible}) {
    final data = codec.encodeMethodCall(
      MethodCall('toggle', {'visible': visible}),
    );
    final completer = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, data, (_) => completer.complete());
    return completer.future;
  }

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

  test('registerHotKey asks native to claim the hotkey', () async {
    await QuakeWindow().registerHotKey();

    final expected = 'registerHotKey';
    expect(calls.single.method, expected);
  });

  test('show asks native to reveal the window', () async {
    await QuakeWindow().show();

    final expected = 'show';
    expect(calls.single.method, expected);
  });

  test('hide asks native to conceal the window', () async {
    await QuakeWindow().hide();

    final expected = 'hide';
    expect(calls.single.method, expected);
  });

  test('a toggle while visible asks native to hide', () async {
    QuakeWindow();
    await sendToggle(visible: true);

    final expected = 'hide';
    expect(calls.single.method, expected);
  });

  test('a toggle while hidden asks native to show', () async {
    QuakeWindow();
    await sendToggle(visible: false);

    final expected = 'show';
    expect(calls.single.method, expected);
  });
}

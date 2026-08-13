import 'package:flutter/services.dart';

/// Drives the quake instance's global hotkey and window visibility.
///
/// Dart decides what happens; native (`QuakeMode` on macOS, the `WM_HOTKEY`
/// handler in `flutter_window.cpp` on Windows) only reports the hotkey firing
/// and the window's visibility at that moment, then carries out whichever of
/// [show] or [hide] Dart calls back with. Geometry is layered on top of
/// [show] in a later step — for now it is called with no frame, and native
/// leaves the window wherever it already sits.
class QuakeWindow {
  QuakeWindow() : _channel = const MethodChannel('orthanc/quake') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  /// Claims the global hotkey. A no-op if another process already holds it —
  /// native swallows that failure, since it just means some other app owns
  /// the chord.
  Future<void> registerHotKey() => _channel.invokeMethod('registerHotKey');

  Future<void> show() => _channel.invokeMethod('show');

  Future<void> hide() => _channel.invokeMethod('hide');

  Future<void> _handle(MethodCall call) async {
    if (call.method != 'toggle') return;
    final wasVisible = (call.arguments as Map)['visible'] as bool;
    if (wasVisible) {
      await hide();
    } else {
      await show();
    }
  }
}

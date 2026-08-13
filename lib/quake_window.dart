import 'dart:io';

import 'package:flutter/services.dart';

import 'quake_geometry.dart';
import 'quake_geometry_store.dart';

/// Drives the quake instance's global hotkey, geometry, and window
/// visibility. Dart decides what happens; native (`QuakeMode` on macOS, the
/// `WM_HOTKEY` handler in `flutter_window.cpp` on Windows) only reports the
/// hotkey firing and the window's visibility at that moment, answers
/// [reveal]'s query for the screen under the cursor, and carries out
/// whichever of `show`/`hide` Dart calls back with.
class QuakeWindow {
  QuakeWindow({required this.geometryFile})
    : _channel = const MethodChannel('orthanc/quake') {
    _channel.setMethodCallHandler(_handle);
  }

  /// Where this instance's saved window size lives — see
  /// `quake_geometry_store.dart`.
  final File geometryFile;
  final MethodChannel _channel;

  /// Claims the global hotkey. A no-op if another process already holds it —
  /// native swallows that failure, since it just means some other app owns
  /// the chord.
  Future<void> registerHotKey() => _channel.invokeMethod('registerHotKey');

  /// Shows the window, snapped to the top edge of whichever screen the
  /// cursor is on right now — full width and half height by default, or the
  /// last size the user resized it to. The one path every reveal goes
  /// through: launch, a hotkey press, and a cross-process summon alike.
  Future<void> reveal() async {
    final screenReply = await _channel.invokeMethod('currentScreen') as Map;
    final screen = (
      x: (screenReply['x'] as num).toDouble(),
      y: (screenReply['y'] as num).toDouble(),
      width: (screenReply['width'] as num).toDouble(),
      height: (screenReply['height'] as num).toDouble(),
    );
    final frame = quakeFrame(
      screen: screen,
      saved: readQuakeGeometry(file: geometryFile),
    );
    await _channel.invokeMethod('show', {
      'x': frame.x,
      'y': frame.y,
      'width': frame.width,
      'height': frame.height,
    });
  }

  Future<void> hide() => _channel.invokeMethod('hide');

  Future<void> _handle(MethodCall call) async {
    if (call.method != 'toggle') return;
    final wasVisible = (call.arguments as Map)['visible'] as bool;
    if (wasVisible) {
      await hide();
    } else {
      await reveal();
    }
  }
}

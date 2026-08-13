import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/quake_geometry.dart';

void main() {
  const screen = (x: 0.0, y: 0.0, width: 1920.0, height: 1080.0);

  test('spans the full screen width by default', () {
    final expected = screen.width;

    final result = quakeFrame(screen: screen);

    expect(result.width, expected);
  });

  test('defaults to half the screen height', () {
    final expected = screen.height / 2;

    final result = quakeFrame(screen: screen);

    expect(result.height, expected);
  });

  test('snaps to the top edge of the screen', () {
    final expected = screen.y;

    final result = quakeFrame(screen: screen);

    expect(result.y, expected);
  });

  test('centres a saved width narrower than the screen', () {
    final expected = (screen.width - 800.0) / 2;

    final result = quakeFrame(
      screen: screen,
      saved: (width: 800.0, height: 400.0),
    );

    expect(result.x, expected);
  });

  test('clamps a saved width from a wider monitor to this screen', () {
    final expected = screen.width;

    final result = quakeFrame(
      screen: screen,
      saved: (width: 3840.0, height: 400.0),
    );

    expect(result.width, expected);
  });

  test('floors a saved size below the minimum', () {
    final result = quakeFrame(
      screen: screen,
      saved: (width: 100.0, height: 50.0),
    );

    expect(result.width, minQuakeWidth);
    expect(result.height, minQuakeHeight);
  });

  test('offsets a centred window by the screen origin', () {
    const secondary = (x: 1920.0, y: 100.0, width: 1440.0, height: 900.0);
    final expected = secondary.x + (secondary.width - 800.0) / 2;

    final result = quakeFrame(
      screen: secondary,
      saved: (width: 800.0, height: 400.0),
    );

    expect(result.x, expected);
    expect(result.y, secondary.y);
  });
}

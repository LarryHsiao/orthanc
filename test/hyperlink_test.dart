import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/hyperlink.dart';

void main() {
  group('isHyperlinkModifierPressed', () {
    test('Windows: control held is the modifier', () {
      const expected = true;

      final result = isHyperlinkModifierPressed(
        isWindows: true,
        isControlPressed: true,
        isMetaPressed: false,
      );

      expect(result, expected);
    });

    test('Windows: meta held is not the modifier', () {
      const expected = false;

      final result = isHyperlinkModifierPressed(
        isWindows: true,
        isControlPressed: false,
        isMetaPressed: true,
      );

      expect(result, expected);
    });

    test('Windows: neither held is not the modifier', () {
      const expected = false;

      final result = isHyperlinkModifierPressed(
        isWindows: true,
        isControlPressed: false,
        isMetaPressed: false,
      );

      expect(result, expected);
    });

    test('macOS: meta held is the modifier', () {
      const expected = true;

      final result = isHyperlinkModifierPressed(
        isWindows: false,
        isControlPressed: false,
        isMetaPressed: true,
      );

      expect(result, expected);
    });

    test('macOS: control held is not the modifier', () {
      const expected = false;

      final result = isHyperlinkModifierPressed(
        isWindows: false,
        isControlPressed: true,
        isMetaPressed: false,
      );

      expect(result, expected);
    });
  });

  group('isLaunchableHyperlink', () {
    test('http scheme is launchable', () {
      const expected = true;

      final result = isLaunchableHyperlink('http://example.com');

      expect(result, expected);
    });

    test('https scheme is launchable', () {
      const expected = true;

      final result = isLaunchableHyperlink('https://example.com/path?x=1');

      expect(result, expected);
    });

    test('file scheme is not launchable', () {
      const expected = false;

      final result = isLaunchableHyperlink('file:///etc/passwd');

      expect(result, expected);
    });

    test('a custom scheme is not launchable', () {
      const expected = false;

      final result = isLaunchableHyperlink('vscode://file/foo.dart');

      expect(result, expected);
    });

    test('null is not launchable', () {
      const expected = false;

      final result = isLaunchableHyperlink(null);

      expect(result, expected);
    });

    test('an unparseable uri is not launchable', () {
      const expected = false;

      final result = isLaunchableHyperlink('%');

      expect(result, expected);
    });
  });
}

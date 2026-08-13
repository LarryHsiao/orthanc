import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/new_instance.dart';
import 'package:path/path.dart' as p;

void main() {
  test('opens the enclosing app bundle on macOS', () {
    final bundle = p.join('/Applications', 'Orthanc.app');
    final expected = (
      executable: '/usr/bin/open',
      arguments: ['-n', '-a', bundle, '--args', 'secondary'],
    );

    final result = newInstanceCommand(
      isMacOS: true,
      resolvedExecutable: p.join(bundle, 'Contents', 'MacOS', 'orthanc'),
    );

    // Field by field: a record holding a List compares that list by
    // identity, so the whole record never equals an identically-shaped one.
    expect(result.executable, expected.executable);
    expect(result.arguments, expected.arguments);
  });

  test('starts the executable directly off macOS', () {
    final executable = p.join('C:', 'Orthanc', 'orthanc.exe');
    final expected = (executable: executable, arguments: ['secondary']);

    final result = newInstanceCommand(
      isMacOS: false,
      resolvedExecutable: executable,
    );

    expect(result.executable, expected.executable);
    expect(result.arguments, expected.arguments);
  });

  test('opens the quake instance on macOS', () {
    final bundle = p.join('/Applications', 'Orthanc.app');
    final expected = (
      executable: '/usr/bin/open',
      arguments: ['-n', '-a', bundle, '--args', 'quake'],
    );

    final result = newInstanceCommand(
      isMacOS: true,
      resolvedExecutable: p.join(bundle, 'Contents', 'MacOS', 'orthanc'),
      kind: InstanceKind.quake,
    );

    expect(result.executable, expected.executable);
    expect(result.arguments, expected.arguments);
  });

  test('starts the quake instance directly off macOS', () {
    final executable = p.join('C:', 'Orthanc', 'orthanc.exe');
    final expected = (executable: executable, arguments: ['quake']);

    final result = newInstanceCommand(
      isMacOS: false,
      resolvedExecutable: executable,
      kind: InstanceKind.quake,
    );

    expect(result.executable, expected.executable);
    expect(result.arguments, expected.arguments);
  });

  test('the first instance gets no extra argument, on either platform', () {
    final bundle = p.join('/Applications', 'Orthanc.app');
    final macResult = newInstanceCommand(
      isMacOS: true,
      resolvedExecutable: p.join(bundle, 'Contents', 'MacOS', 'orthanc'),
      kind: InstanceKind.first,
    );
    expect(macResult.arguments, ['-n', '-a', bundle]);

    final windowsResult = newInstanceCommand(
      isMacOS: false,
      resolvedExecutable: p.join('C:', 'Orthanc', 'orthanc.exe'),
      kind: InstanceKind.first,
    );
    expect(windowsResult.arguments, isEmpty);
  });

  group('instanceKind', () {
    test('no arguments means the first instance', () {
      final expected = InstanceKind.first;
      expect(instanceKind(arguments: const []), expected);
    });

    test('the secondary argument means a secondary instance', () {
      final expected = InstanceKind.secondary;
      expect(instanceKind(arguments: const ['secondary']), expected);
    });

    test('the quake argument means the quake instance', () {
      final expected = InstanceKind.quake;
      expect(instanceKind(arguments: const ['quake']), expected);
    });

    test('quake takes precedence when both arguments are present', () {
      final expected = InstanceKind.quake;
      expect(instanceKind(arguments: const ['quake', 'secondary']), expected);
    });
  });
}

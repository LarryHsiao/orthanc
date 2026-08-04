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
}

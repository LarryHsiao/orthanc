import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/quake_geometry_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'orthanc_quake_geometry_store_test',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('reading a missing geometry file returns null', () {
    const expected = null;
    final file = quakeGeometryFile(supportDir: tempDir);

    final result = readQuakeGeometry(file: file);

    expect(result, expected);
  });

  test('writing then reading round-trips the size', () {
    const expected = (width: 1200.0, height: 500.0);
    final file = quakeGeometryFile(supportDir: tempDir);

    writeQuakeGeometry(expected, file: file);
    final result = readQuakeGeometry(file: file);

    expect(result, expected);
  });

  test('writing leaves no leftover temp file beside quake_geometry.json', () {
    const expected = <String>[];
    final file = quakeGeometryFile(supportDir: tempDir);

    writeQuakeGeometry((width: 800.0, height: 400.0), file: file);
    final result = tempDir
        .listSync()
        .map((entity) => p.basename(entity.path))
        .where((name) => name != p.basename(file.path))
        .toList();

    expect(result, expected);
  });

  test('reading a corrupt geometry file returns null', () {
    const expected = null;
    final file = quakeGeometryFile(supportDir: tempDir);
    file.createSync(recursive: true);
    file.writeAsStringSync('{not valid json');

    final result = readQuakeGeometry(file: file);

    expect(result, expected);
  });

  test('reading valid JSON with a wrong-typed field returns null', () {
    const expected = null;
    final file = quakeGeometryFile(supportDir: tempDir);
    file.createSync(recursive: true);
    file.writeAsStringSync('{"width": "not a number", "height": 400}');

    final result = readQuakeGeometry(file: file);

    expect(result, expected);
  });
}

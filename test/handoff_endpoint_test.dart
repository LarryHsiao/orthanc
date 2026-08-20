import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/handoff_endpoint.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'orthanc_handoff_endpoint_test',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('handoffEndpointFile', () {
    test('names the endpoint after the pid alone', () {
      final expected = p.join(tempDir.path, 'handoff-4242.sock');

      final result = handoffEndpointFile(supportDir: tempDir, pid: 4242);

      expect(result.path, expected);
    });

    test('two different pids never collide', () {
      final first = handoffEndpointFile(supportDir: tempDir, pid: 1);
      final second = handoffEndpointFile(supportDir: tempDir, pid: 2);

      expect(first.path, isNot(second.path));
    });
  });

  group('crossInstanceHandoffSupported', () {
    test('disabled on Windows', () {
      const expected = false;

      final result = crossInstanceHandoffSupported(isWindows: true);

      expect(result, expected);
    });

    test('enabled off Windows', () {
      const expected = true;

      final result = crossInstanceHandoffSupported(isWindows: false);

      expect(result, expected);
    });
  });

  group('staleHandoffEndpoints', () {
    test('finds an endpoint whose pid is no longer alive', () {
      const expected = 1;
      handoffEndpointFile(
        supportDir: tempDir,
        pid: 999,
      ).createSync(recursive: true);

      final result = staleHandoffEndpoints(
        supportDir: tempDir,
        isAlive: (pid) => false,
      );

      expect(result.length, expected);
      expect(p.basename(result.single.path), 'handoff-999.sock');
    });

    test('leaves an endpoint whose pid is still alive alone', () {
      const expected = <String>[];
      handoffEndpointFile(
        supportDir: tempDir,
        pid: 999,
      ).createSync(recursive: true);

      final result = staleHandoffEndpoints(
        supportDir: tempDir,
        isAlive: (pid) => true,
      );

      expect(result, expected);
    });

    test('ignores a file that does not match the endpoint naming pattern', () {
      const expected = <String>[];
      File(p.join(tempDir.path, 'settings.json')).createSync(recursive: true);

      final result = staleHandoffEndpoints(
        supportDir: tempDir,
        isAlive: (pid) => false,
      );

      expect(result, expected);
    });

    test('returns empty for a support directory that does not exist yet', () {
      const expected = <String>[];
      final missing = Directory(p.join(tempDir.path, 'does-not-exist'));

      final result = staleHandoffEndpoints(
        supportDir: missing,
        isAlive: (pid) => false,
      );

      expect(result, expected);
    });

    test('passes the exact pid parsed from the filename to isAlive', () {
      const expected = 4242;
      handoffEndpointFile(
        supportDir: tempDir,
        pid: 4242,
      ).createSync(recursive: true);
      int? seenPid;

      staleHandoffEndpoints(
        supportDir: tempDir,
        isAlive: (pid) {
          seenPid = pid;
          return true;
        },
      );

      expect(seenPid, expected);
    });

    test('sweeps only the stale ones out of a mix of live and dead', () {
      const expected = 'handoff-2.sock';
      handoffEndpointFile(supportDir: tempDir, pid: 1).createSync();
      handoffEndpointFile(supportDir: tempDir, pid: 2).createSync();
      final alive = {1};

      final result = staleHandoffEndpoints(
        supportDir: tempDir,
        isAlive: alive.contains,
      );

      expect(result.length, 1);
      expect(p.basename(result.single.path), expected);
    });
  });

  group('liveHandoffEndpoints', () {
    test('excludes ownPid even when it is alive', () {
      const expected = <int>[];
      handoffEndpointFile(supportDir: tempDir, pid: 111).createSync();

      final result = liveHandoffEndpoints(
        supportDir: tempDir,
        ownPid: 111,
        isAlive: (pid) => true,
      );

      expect(result.map((e) => e.pid).toList(), expected);
    });

    test('excludes a dead pid even when it is not ownPid', () {
      const expected = <int>[];
      handoffEndpointFile(supportDir: tempDir, pid: 222).createSync();

      final result = liveHandoffEndpoints(
        supportDir: tempDir,
        ownPid: 111,
        isAlive: (pid) => false,
      );

      expect(result.map((e) => e.pid).toList(), expected);
    });

    test('finds another live instance, paired with its pid', () {
      const expected = 222;
      handoffEndpointFile(supportDir: tempDir, pid: 222).createSync();

      final result = liveHandoffEndpoints(
        supportDir: tempDir,
        ownPid: 111,
        isAlive: (pid) => true,
      );

      expect(result.length, 1);
      expect(result.single.pid, expected);
      expect(p.basename(result.single.file.path), 'handoff-222.sock');
    });

    test('a mix of self, dead, and live keeps only the live other', () {
      const expected = 333;
      handoffEndpointFile(supportDir: tempDir, pid: 111).createSync(); // self
      handoffEndpointFile(supportDir: tempDir, pid: 222).createSync(); // dead
      handoffEndpointFile(supportDir: tempDir, pid: 333).createSync(); // live
      final alive = {111, 333};

      final result = liveHandoffEndpoints(
        supportDir: tempDir,
        ownPid: 111,
        isAlive: alive.contains,
      );

      expect(result.length, 1);
      expect(result.single.pid, expected);
    });

    test('returns empty for a support directory that does not exist yet', () {
      const expected = <int>[];
      final missing = Directory(p.join(tempDir.path, 'does-not-exist'));

      final result = liveHandoffEndpoints(
        supportDir: missing,
        ownPid: 111,
        isAlive: (pid) => true,
      );

      expect(result.map((e) => e.pid).toList(), expected);
    });
  });
}

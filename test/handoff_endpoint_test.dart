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

  group('firstAcceptingEndpoint', () {
    HandoffEndpoint endpoint(int pid) =>
        (file: handoffEndpointFile(supportDir: tempDir, pid: pid), pid: pid);

    test(
      'skips a rejecting endpoint and returns the next that accepts',
      () async {
        final candidates = [endpoint(1), endpoint(2), endpoint(3)];
        final expected = candidates[1];
        final tried = <int>[];

        final result = await firstAcceptingEndpoint(candidates, (
          candidate,
        ) async {
          tried.add(candidate.pid);
          return candidate.pid == 2;
        });

        expect(
          [result, tried],
          [
            expected,
            [1, 2],
          ],
        );
      },
    );

    test('treats a throwing attempt as a rejection and goes on', () async {
      final candidates = [endpoint(1), endpoint(2)];
      final expected = candidates[1];

      final result = await firstAcceptingEndpoint(candidates, (
        candidate,
      ) async {
        if (candidate.pid == 1) throw StateError('dead socket');
        return true;
      });

      expect(result, expected);
    });

    test('returns null when every endpoint rejects', () async {
      final candidates = [endpoint(1), endpoint(2)];

      final result = await firstAcceptingEndpoint(
        candidates,
        (candidate) async => false,
      );

      expect(result, isNull);
    });

    test('returns null for no candidates, trying nothing', () async {
      var attempts = 0;

      final result = await firstAcceptingEndpoint(const [], (candidate) async {
        attempts++;
        return true;
      });

      expect([result, attempts], [null, 0]);
    });
  });

  group('commandNamesExecutable', () {
    test('accepts the full path of the same executable', () {
      const output = '/Applications/orthanc.app/Contents/MacOS/orthanc\n';

      final result = commandNamesExecutable(output, 'orthanc');

      expect(result, isTrue);
    });

    test('rejects an unrelated process that recycled the pid', () {
      const output =
          '/System/Library/ExtensionKit/Extensions/GMSSELFIngestor.appex'
          '/Contents/MacOS/GMSSELFIngestor\n';

      final result = commandNamesExecutable(output, 'orthanc');

      expect(result, isFalse);
    });

    test('rejects a name that merely contains the executable name', () {
      const output = '/usr/local/bin/orthanc-helper\n';

      final result = commandNamesExecutable(output, 'orthanc');

      expect(result, isFalse);
    });

    test('rejects empty output', () {
      final result = commandNamesExecutable('', 'orthanc');

      expect(result, isFalse);
    });
  });

  group('removeStaleHandoffEndpoints', () {
    test('deletes dead endpoints and keeps live ones', () {
      final dead = handoffEndpointFile(supportDir: tempDir, pid: 1)
        ..writeAsStringSync('');
      final live = handoffEndpointFile(supportDir: tempDir, pid: 2)
        ..writeAsStringSync('');

      removeStaleHandoffEndpoints(
        supportDir: tempDir,
        isAlive: (pid) => pid == 2,
      );

      expect([dead.existsSync(), live.existsSync()], [false, true]);
    });

    test('leaves a file outside the endpoint naming pattern alone', () {
      final other = File(p.join(tempDir.path, 'settings.json'))
        ..writeAsStringSync('{}');

      removeStaleHandoffEndpoints(supportDir: tempDir, isAlive: (_) => false);

      expect(other.existsSync(), isTrue);
    });
  });

  group('psSaysLive', () {
    test('exit 0 with the same executable is live', () {
      final result = psSaysLive(
        0,
        '/Applications/orthanc.app/Contents/MacOS/orthanc\n',
        'orthanc',
      );

      expect(result, isTrue);
    });

    test('exit 0 with another executable is not live', () {
      final result = psSaysLive(0, '/usr/sbin/cron\n', 'orthanc');

      expect(result, isFalse);
    });

    test('exit 1 with empty output means no such pid', () {
      final result = psSaysLive(1, '', 'orthanc');

      expect(result, isFalse);
    });

    test('any other failure is read as live, so nothing live is deleted', () {
      final denied = psSaysLive(2, '', 'orthanc');
      final noisy = psSaysLive(1, 'ps: permission denied', 'orthanc');

      expect([denied, noisy], [true, true]);
    });
  });
}

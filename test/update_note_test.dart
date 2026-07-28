import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/update_note.dart';

void main() {
  group('checkForUpdateNote', () {
    test('shows no note on the very first launch (nothing seen yet)', () {
      const expected = false;

      final result = checkForUpdateNote(
        lastSeenVersion: null,
        currentVersion: '1.2.0',
      );

      expect(result.shouldShow, expected);
    });

    test('shows no note when the version is unchanged', () {
      const expected = false;

      final result = checkForUpdateNote(
        lastSeenVersion: '1.2.0',
        currentVersion: '1.2.0',
      );

      expect(result.shouldShow, expected);
    });

    test('shows a note naming the new version when it changed', () {
      const expectedShouldShow = true;
      const expectedVersion = '1.2.0';

      final result = checkForUpdateNote(
        lastSeenVersion: '1.1.0',
        currentVersion: '1.2.0',
      );

      expect(result.shouldShow, expectedShouldShow);
      expect(result.version, expectedVersion);
    });
  });

  group('updateNoteOnLaunch', () {
    test(
      'reads the last-seen version, computes the note, and persists the running version',
      () async {
        const expectedShouldShow = true;
        const expectedVersion = '1.2.0';
        String? written;

        final result = await updateNoteOnLaunch(
          readLastSeenVersion: () async => '1.1.0',
          writeLastSeenVersion: (version) async => written = version,
          currentVersion: '1.2.0',
        );

        expect(result.shouldShow, expectedShouldShow);
        expect(result.version, expectedVersion);
        expect(written, expectedVersion);
      },
    );

    test(
      'persists the running version even on the first launch, so the next launch has something to compare against',
      () async {
        const expectedWritten = '1.2.0';
        String? written;

        final result = await updateNoteOnLaunch(
          readLastSeenVersion: () async => null,
          writeLastSeenVersion: (version) async => written = version,
          currentVersion: '1.2.0',
        );

        expect(result.shouldShow, false);
        expect(written, expectedWritten);
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/session.dart';

void main() {
  test('stores the id and executable it is given', () {
    const expectedId = 'a';
    const expectedExecutable = 'cmd.exe';

    final session = Session(id: expectedId, executable: expectedExecutable);

    expect(session.id, expectedId);
    expect(session.executable, expectedExecutable);
  });

  test('starts idle, titled by its executable', () {
    const expectedTitle = 'cmd.exe';
    const expectedBusy = false;

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.title.value, expectedTitle);
    expect(session.busy.value, expectedBusy);
  });

  test('waits half a second before calling a session idle', () {
    const expected = Duration(milliseconds: 500);

    expect(busyWindow, expected);
  });

  test('dispose() on a never-started session does not throw', () {
    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.dispose, returnsNormally);
  });

  test('dispose() is safe to call twice', () {
    final session = Session(id: 'a', executable: 'cmd.exe');
    session.dispose();

    expect(session.dispose, returnsNormally);
  });
}

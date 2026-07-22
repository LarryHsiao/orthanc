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

  test('starts titled by its executable', () {
    const expectedTitle = 'cmd.exe';

    final session = Session(id: 'a', executable: 'cmd.exe');

    expect(session.title.value, expectedTitle);
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

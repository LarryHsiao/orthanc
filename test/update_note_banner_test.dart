import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/update_note_banner.dart';

void main() {
  testWidgets('names the version that was updated to', (tester) async {
    const expected = 'Updated to v1.2.0';

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateNoteBanner(version: '1.2.0', onDismiss: () {}),
      ),
    );

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('calls onDismiss when the close button is tapped', (
    tester,
  ) async {
    const expected = true;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateNoteBanner(
          version: '1.2.0',
          onDismiss: () => dismissed = true,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(dismissed, expected);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/main.dart';

void main() {
  testWidgets('renders an empty window with no counter UI', (tester) async {
    await tester.pumpWidget(const OrthancApp());

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}

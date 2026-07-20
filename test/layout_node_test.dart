import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/layout_node.dart';

void main() {
  test('a pane node carries its session id', () {
    const expected = 'a';

    const node = PaneNode(expected);

    expect(node.sessionId, expected);
  });

  test('a split node carries its axis, children and ratios', () {
    const expectedAxis = SplitAxis.row;
    const expectedChildren = [PaneNode('a'), PaneNode('b')];
    const expectedRatios = [0.5, 0.5];

    const node = SplitNode(
      axis: expectedAxis,
      children: expectedChildren,
      ratios: expectedRatios,
    );

    expect(node.axis, expectedAxis);
    expect(node.children, expectedChildren);
    expect(node.ratios, expectedRatios);
  });

  test('pane rects of the same numbers are equal', () {
    const expected = PaneRect(left: 0, top: 0, width: 0.5, height: 1);

    const actual = PaneRect(left: 0, top: 0, width: 0.5, height: 1);

    expect(actual, expected);
  });
}

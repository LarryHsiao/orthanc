import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'copy_marker.dart';

/// Where the terminal's cells sit in pixels: the size of one, and the
/// top-left corner of any, scroll position already counted.
class CellGeometry {
  const CellGeometry({required this.cellSize, required this.offsetOf});

  final Size cellSize;
  final Offset Function(CellOffset) offsetOf;
}

/// The geometry of the terminal under [key], or null before it is built.
CellGeometry? terminalGeometry(GlobalKey<TerminalViewState> key) {
  final render = key.currentState?.renderTerminal;
  if (render == null || !render.hasSize) return null;
  return CellGeometry(cellSize: render.cellSize, offsetOf: render.getOffset);
}

/// Draws a chip over every visible `⧉ copy:<name>` marker, so the line reads
/// as a button rather than as text. The terminal's own cells are left
/// untouched beneath: the chip is an overlay, click-through, and the pane's
/// tap handler still does the copying.
class CopyMarkerChips extends StatefulWidget {
  const CopyMarkerChips({
    super.key,
    required this.terminal,
    required this.scrollController,
    required this.geometry,
    required this.textStyle,
    required this.background,
    required this.hoverBackground,
    required this.copiedBackground,
    required this.foreground,
    required this.hovered,
    required this.copied,
  });

  /// Marks each chip's [DecoratedBox], for tests.
  static const chipKey = Key('copy-marker-chip');

  final Terminal terminal;

  /// The controller handed to the [TerminalView] beneath, so a scroll moves
  /// the chips with the rows.
  final ScrollController scrollController;

  /// The terminal's cell geometry, or null before it has been built.
  final CellGeometry? Function() geometry;

  /// The terminal's own text style, so the label fills the cells it covers.
  final TextStyle textStyle;
  final Color background;
  final Color hoverBackground;
  final Color copiedBackground;
  final Color foreground;

  /// The block name currently under the pointer, or null.
  final ValueListenable<String?> hovered;

  /// The block name whose copy just landed, or null. Its chip reads
  /// "Copied" for as long as this holds the name.
  final ValueListenable<String?> copied;

  @override
  State<CopyMarkerChips> createState() => _CopyMarkerChipsState();
}

class _CopyMarkerChipsState extends State<CopyMarkerChips> {
  @override
  void initState() {
    super.initState();
    widget.terminal.addListener(_repaint);
    widget.scrollController.addListener(_repaint);
    widget.hovered.addListener(_repaint);
    widget.copied.addListener(_repaint);
  }

  @override
  void didUpdateWidget(CopyMarkerChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_repaint);
      widget.terminal.addListener(_repaint);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_repaint);
      widget.scrollController.addListener(_repaint);
    }
    if (oldWidget.hovered != widget.hovered) {
      oldWidget.hovered.removeListener(_repaint);
      widget.hovered.addListener(_repaint);
    }
    if (oldWidget.copied != widget.copied) {
      oldWidget.copied.removeListener(_repaint);
      widget.copied.addListener(_repaint);
    }
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_repaint);
    widget.scrollController.removeListener(_repaint);
    widget.hovered.removeListener(_repaint);
    widget.copied.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            Stack(children: _chips(constraints.maxHeight)),
      ),
    );
  }

  List<Widget> _chips(double viewportHeight) {
    final geometry = widget.geometry();
    if (geometry == null) return const [];
    final cell = geometry.cellSize;
    final scrolled = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    final firstRow = (scrolled / cell.height).floor();
    final lastRow = ((scrolled + viewportHeight) / cell.height).ceil();
    return [
      for (final span in copyMarkerSpans(
        widget.terminal.buffer,
        firstRow,
        lastRow,
      ))
        _chip(span, geometry),
    ];
  }

  Widget _chip(CopyMarkerSpan span, CellGeometry geometry) {
    final origin = geometry.offsetOf(CellOffset(span.startColumn, span.row));
    final cells = span.endColumn - span.startColumn;
    final done = widget.copied.value == span.name;
    final hot = widget.hovered.value == span.name;
    return Positioned(
      left: origin.dx,
      top: origin.dy,
      width: cells * geometry.cellSize.width,
      height: geometry.cellSize.height,
      child: DecoratedBox(
        key: CopyMarkerChips.chipKey,
        decoration: BoxDecoration(
          color: done
              ? widget.copiedBackground
              : hot
              ? widget.hoverBackground
              : widget.background,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          _label(span, done),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: widget.textStyle.copyWith(
            color: widget.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// The slice of the chip's text that lies over [span]'s cells. The text is
  /// padded to the marker's full width, so "Copied" never leaves the cells
  /// beyond it showing the label beneath.
  String _label(CopyMarkerSpan span, bool done) {
    final markerWidth = '⧉ copy:${span.name}'.length;
    final text = done ? '✓ Copied' : '⧉ Copy ${span.name}';
    return text
        .padRight(markerWidth)
        .substring(
          span.markerOffset,
          span.markerOffset + span.endColumn - span.startColumn,
        );
  }
}

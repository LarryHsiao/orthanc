/// Below this, the terminal becomes too cramped to be worth showing.
const minQuakeWidth = 400.0;
const minQuakeHeight = 200.0;

/// The quake window's default height, as a fraction of the screen, when no
/// size has been saved yet.
const defaultQuakeHeightFraction = 0.5;

/// Computes the quake window's frame for [screen] — the work area of the
/// display under the cursor — honoring a persisted [saved] size when there
/// is one.
///
/// Full width and half height by default, snapped to the top edge and
/// horizontally centred. Width and height are always clamped to the screen
/// and to a sane floor, so a saved size from a wider monitor (or corrupt
/// state) never produces an off-screen or invisible window. Position is
/// never persisted — only size — so the window always reappears on
/// whichever screen the cursor is on, at that screen's top edge.
///
/// Works in one coordinate convention throughout: top-left origin, y growing
/// downward. Native flips to AppKit's bottom-left-origin convention on
/// macOS; Windows needs no flip, since `MONITORINFO` already matches.
({double x, double y, double width, double height}) quakeFrame({
  required ({double x, double y, double width, double height}) screen,
  ({double width, double height})? saved,
}) {
  final width = (saved?.width ?? screen.width).clamp(
    minQuakeWidth,
    screen.width,
  );
  final height = (saved?.height ?? screen.height * defaultQuakeHeightFraction)
      .clamp(minQuakeHeight, screen.height);
  return (
    x: screen.x + (screen.width - width) / 2,
    y: screen.y,
    width: width,
    height: height,
  );
}

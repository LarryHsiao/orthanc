import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

private let quakeArgument = "quake"

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var quakeMode: QuakeMode?

  // A borderless window (no .titled in its style mask) cannot become key by
  // default — AppKit's own NSWindow.canBecomeKey returns false for one
  // unless overridden, which silently blocks all keyboard input from ever
  // reaching it. Harmless for an ordinary titled window, which already
  // returns true here regardless.
  override var canBecomeKey: Bool { true }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    if CommandLine.arguments.contains(quakeArgument) {
      let mode = QuakeMode(
        window: self,
        messenger: flutterViewController.engine.binaryMessenger
      )
      mode.start()
      quakeMode = mode
      delegate = self
    }

    super.awakeFromNib()
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    quakeMode?.windowDidEndLiveResize()
  }
}

private let quakeHotKeySignature: OSType = 0x6f72_7468  // 'orth'
private let quakeHotKeyId: UInt32 = 1
private let quakeSlideDuration: TimeInterval = 0.15

/// Owns the quake instance's global hotkey and reports its presses to Dart
/// over the `orthanc/quake` channel. Dart decides whether to show or hide;
/// this class only carries out the `show`/`hide` calls it gets back — see
/// `quake_window.dart` for the Dart side of the same contract.
private final class QuakeMode {
  private let window: NSWindow
  private let channel: FlutterMethodChannel
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "orthanc/quake", binaryMessenger: messenger)
  }

  /// The window starts ordered out — it must, for the eventual slide-down
  /// animation to start from off-screen — and stays that way until Dart asks
  /// for `show`. AppKit treats `orderOut` on the app's only window the same
  /// as a real close for `applicationShouldTerminateAfterLastWindowClosed`
  /// — see `AppDelegate.swift`, which answers `false` for the quake
  /// instance so hiding never quits it.
  ///
  /// Dropping `.titled` removes the title bar and its traffic-light buttons,
  /// for the borderless look a drop-down terminal wants — `.resizable` is a
  /// separate style-mask bit, so edge-drag resizing (and the
  /// `windowDidEndLiveResize` it drives) still works without it. With no
  /// close button, `Cmd+Q` is the quake instance's quit gesture instead.
  func start() {
    window.styleMask.remove(.titled)
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.orderOut(nil)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "registerHotKey":
      registerHotKey()
      result(nil)
    case "currentScreen":
      result(currentScreenPayload())
    case "show":
      slideIn(to: call.arguments as? [String: Any])
      result(nil)
    case "hide":
      window.orderOut(nil)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The work area (excludes the menu bar and Dock) of the display under the
  /// cursor, flipped to the top-left-origin, y-down convention
  /// `quake_geometry.dart`'s `quakeFrame` works in.
  private func currentScreenPayload() -> [String: Double] {
    let mouseLocation = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
      ?? window.screen
      ?? NSScreen.main
    guard let screen else {
      return ["x": 0, "y": 0, "width": 800, "height": 600]
    }
    let flipped = flip(screen.visibleFrame)
    return [
      "x": flipped.x,
      "y": flipped.y,
      "width": flipped.width,
      "height": flipped.height,
    ]
  }

  /// Orders the window front at [frame], sliding down from directly above
  /// the visible area rather than simply appearing there. Missing or
  /// malformed frame data (only possible if Dart's contract is broken)
  /// falls back to ordering front wherever the window already sits, rather
  /// than not showing it at all.
  private func slideIn(to frame: [String: Any]?) {
    guard let frames = slideFrames(for: frame) else {
      raiseWindow()
      return
    }
    window.setFrame(frames.start, display: false)
    raiseWindow()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = quakeSlideDuration
      window.animator().setFrame(frames.target, display: true)
    }
  }

  /// Activating the app alone can lose a race against whatever else is
  /// frontmost — `orderFrontRegardless` is the stronger guarantee, bypassing
  /// the app-activation state entirely to force the window forward.
  private func raiseWindow() {
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  /// The animation's start and end rects, flipped from [frame]'s top-left,
  /// y-down convention to AppKit's bottom-left origin — around the same
  /// primary-display reference line `flip` used. [start]'s bottom edge sits
  /// exactly at [target]'s top edge: one window-height further up, fully off
  /// the visible area.
  private func slideFrames(
    for frame: [String: Any]?
  ) -> (start: NSRect, target: NSRect)? {
    guard let frame,
      let x = frame["x"] as? Double,
      let y = frame["y"] as? Double,
      let width = frame["width"] as? Double,
      let height = frame["height"] as? Double
    else { return nil }
    let primaryHeight = NSScreen.screens.first?.frame.height ?? (y + height)
    let target = NSRect(
      x: x, y: primaryHeight - y - height, width: width, height: height)
    let start = NSRect(x: x, y: primaryHeight - y, width: width, height: height)
    return (start: start, target: target)
  }

  /// Converts an AppKit rect (bottom-left origin, y growing upward, global
  /// coordinates) to the top-left-origin, y-down convention. The primary
  /// display's height is the one fixed line every screen's y flips around,
  /// since only the primary screen is guaranteed an origin of (0, 0).
  private func flip(
    _ rect: NSRect
  ) -> (x: Double, y: Double, width: Double, height: Double) {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
    return (
      x: rect.minX,
      y: primaryHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }

  private func registerHotKey() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return noErr }
        Unmanaged<QuakeMode>.fromOpaque(userData).takeUnretainedValue().hotKeyPressed()
        return noErr
      },
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
    let hotKeyId = EventHotKeyID(signature: quakeHotKeySignature, id: quakeHotKeyId)
    // A non-zero status means some other app already owns the chord — that
    // failure is swallowed by design; the window stays reachable from the
    // menu item either way.
    RegisterEventHotKey(
      UInt32(kVK_ANSI_Grave),
      UInt32(cmdKey),
      hotKeyId,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
  }

  private func hotKeyPressed() {
    channel.invokeMethod("toggle", arguments: ["visible": window.isVisible])
  }

  /// Fires once, at the end of a user's resize drag — never for a
  /// programmatic `setFrame` (that never triggers a live-resize sequence),
  /// so `reveal()`'s own frame changes can never be mistaken for this.
  func windowDidEndLiveResize() {
    let size = window.frame.size
    channel.invokeMethod("resized", arguments: [
      "width": Double(size.width),
      "height": Double(size.height),
    ])
  }
}

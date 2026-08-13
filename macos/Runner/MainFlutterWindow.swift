import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

private let quakeArgument = "quake"

class MainFlutterWindow: NSWindow {
  private var quakeMode: QuakeMode?

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
    }

    super.awakeFromNib()
  }
}

private let quakeHotKeySignature: OSType = 0x6f72_7468  // 'orth'
private let quakeHotKeyId: UInt32 = 1

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
  /// for `show`. `orderOut` does not close the window, so
  /// `applicationShouldTerminateAfterLastWindowClosed` never fires from this.
  func start() {
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
      applyFrame(call.arguments as? [String: Any])
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
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

  private func applyFrame(_ frame: [String: Any]?) {
    guard let frame,
      let x = frame["x"] as? Double,
      let y = frame["y"] as? Double,
      let width = frame["width"] as? Double,
      let height = frame["height"] as? Double
    else { return }
    // Flip back from top-left, y-down to AppKit's bottom-left origin, around
    // the same primary-display reference line `flip` used.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? (y + height)
    window.setFrame(
      NSRect(x: x, y: primaryHeight - y - height, width: width, height: height),
      display: true
    )
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
      UInt32(controlKey),
      hotKeyId,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
  }

  private func hotKeyPressed() {
    channel.invokeMethod("toggle", arguments: ["visible": window.isVisible])
  }
}

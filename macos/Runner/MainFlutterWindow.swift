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
    case "show":
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

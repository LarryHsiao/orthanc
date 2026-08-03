import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Keeps each secondary NSWindow alive for as long as it's open — nothing
  // else retains it, and without this it would deallocate (and silently
  // close) the moment createSecondaryWindow() returns. Entries are removed
  // again on that window's own close, in createSecondaryWindow() below.
  private var secondaryWindows: [NSWindow] = []

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Wires the `orthanc/system_menu` channel's `newWindow` method on
  // `engine` to createSecondaryWindow() — called once for the primary
  // engine (from MainFlutterWindow) and once for every secondary engine
  // this itself creates, so Cmd+N works from any open window.
  func configureSystemMenuChannel(on engine: FlutterEngine) {
    let channel = FlutterMethodChannel(
      name: "orthanc/system_menu",
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "newWindow" {
        self?.createSecondaryWindow()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // macOS has no FlutterEngineGroup (that's iOS/Android-only) — each
  // additional window's engine is built directly: construct it, run it,
  // then wrap it in a FlutterViewController. dartEntrypointArguments tells
  // this window's Dart main() it's secondary, so it skips the update
  // check and opens with a single default pane rather than copying any
  // other window's layout.
  private func createSecondaryWindow() {
    let project = FlutterDartProject()
    project.dartEntrypointArguments = ["secondary"]
    let engine = FlutterEngine(name: "orthanc-secondary", project: project)
    // Fails silently by design, matching this app's existing precedent for
    // rare, low-stakes failures (AppRoot's update-check) — the user can
    // just press Cmd+N again rather than seeing an error dialog.
    guard engine.run(withEntrypoint: nil) else { return }

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    RegisterGeneratedPlugins(registry: controller)
    configureSystemMenuChannel(on: engine)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = controller
    window.center()
    window.makeKeyAndOrderFront(nil)

    secondaryWindows.append(window)
    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      self?.secondaryWindows.removeAll { $0 === window }
    }
  }
}

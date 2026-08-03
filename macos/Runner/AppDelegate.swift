import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // Keeps each secondary NSWindow alive for as long as it's open — nothing
  // else retains it, and without this it would deallocate (and silently
  // close) the moment createSecondaryWindow() returns. Entries are removed
  // again on that window's own close, in createSecondaryWindow() below.
  private var secondaryWindows: [NSWindow] = []
  // Holds each secondary window's willCloseNotification observer token,
  // keyed by the window's identity, so it can be removed from
  // NotificationCenter the moment that window closes — otherwise the
  // observer block (and its captured window) would linger in
  // NotificationCenter's table for the app's entire lifetime.
  private var secondaryWindowObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Wires the `orthanc/system_menu` channel's `newWindow`/`closeWindow`
  // methods on `engine` to this window specifically — called once for the
  // primary engine (from MainFlutterWindow, passing its own `self`) and
  // once for every secondary engine this itself creates, so both Cmd+N and
  // "close this window" work from any open window.
  //
  // Closing the primary window while secondaries remain open is a named,
  // accepted limitation for now: MainFlutterWindow will close (hide) like
  // any other window here, but nothing tears its engine/session resources
  // down while other windows keep the app alive — full symmetry with
  // secondary-window teardown is a larger native change than this fix
  // covers.
  func configureSystemMenuChannel(on engine: FlutterEngine, window: NSWindow) {
    let channel = FlutterMethodChannel(
      name: "orthanc/system_menu",
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self, weak window] call, result in
      switch call.method {
      case "newWindow":
        self?.createSecondaryWindow()
        result(nil)
      case "closeWindow":
        let code = (call.arguments as? Int).map { Int32($0) } ?? 0
        window?.close()
        // Once this was genuinely the last open window, AppKit's own
        // applicationShouldTerminateAfterLastWindowClosed would otherwise
        // terminate with exit code 0 — exit directly instead, so the
        // closing shell's exit code still becomes the process's, matching
        // this app's pre-multi-window behavior.
        if NSApp.windows.allSatisfy({ !$0.isVisible }) {
          exit(code)
        }
        result(nil)
      default:
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

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    // A programmatically-created NSWindow defaults isReleasedWhenClosed to
    // true, which sends an extra release on close on top of ARC's normal
    // tracking of the strong reference this file keeps in
    // secondaryWindows — disable it so that array is the only thing whose
    // release matters.
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.center()
    window.makeKeyAndOrderFront(nil)
    configureSystemMenuChannel(on: engine, window: window)

    secondaryWindows.append(window)
    // Both self and window are captured weakly so this block never keeps
    // the window (and its controller/engine) alive on its own. The array
    // and observer cleanup are deferred to the next run-loop turn via
    // DispatchQueue.main.async so -[NSWindow close] has fully finished
    // before this drops what may be the last strong reference to it.
    let windowId = ObjectIdentifier(window)
    secondaryWindowObservers[windowId] = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: window,
      queue: .main
    ) { [weak self, weak window] _ in
      guard let window = window else { return }
      DispatchQueue.main.async {
        self?.secondaryWindows.removeAll { $0 === window }
        if let observer = self?.secondaryWindowObservers.removeValue(forKey: windowId) {
          NotificationCenter.default.removeObserver(observer)
        }
      }
    }
  }
}

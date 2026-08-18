import Cocoa
import FlutterMacOS

private let quakeArgument = "quake"

@main
class AppDelegate: FlutterAppDelegate {
  // AppKit treats `orderOut` on the app's only window the same as a real
  // close here — so the quake instance, which hides via `orderOut` on every
  // hotkey toggle (`MainFlutterWindow.swift`), must answer `false` or it
  // quits on every hide. `Cmd+Q` is its quit gesture instead. Every other
  // instance keeps the standard `true`: closing its one and only window is
  // meant to end the process.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !CommandLine.arguments.contains(quakeArgument)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

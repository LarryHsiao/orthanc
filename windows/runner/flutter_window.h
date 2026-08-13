#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |quake| marks this as the dedicated drop-down-terminal instance, which
  // registers a global hotkey and starts hidden instead of shown.
  explicit FlutterWindow(const flutter::DartProject& project, bool quake);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Dispatches a call arriving on |quake_channel_|. Dart decides whether to
  // show or hide; this only carries out what it asks for.
  void HandleQuakeMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Restores the window, positions it per |arguments| (a {x, y, width,
  // height} map, or null to leave the frame as it is), and forces it to the
  // foreground.
  void ShowQuakeWindow(const flutter::EncodableValue* arguments);

  // The project to run.
  flutter::DartProject project_;

  // Whether this is the dedicated quake instance.
  bool quake_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Notifies Dart when the title bar's "Settings…" system-menu item fires.
  // macOS needs no native equivalent — its Settings entry lives in
  // PlatformMenuBar, in Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_menu_channel_;

  // Drives the quake instance's global hotkey and window visibility. Only
  // constructed when |quake_| is true — see `quake_window.dart` for the Dart
  // side of the same contract.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      quake_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

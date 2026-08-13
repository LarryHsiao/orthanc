#include "flutter_window.h"

#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Must be a multiple of 16 — Windows reserves the low 4 bits of a
// WM_SYSCOMMAND wParam for its own built-in commands.
constexpr UINT_PTR kSettingsMenuId = 0x1000;
constexpr UINT_PTR kShortcutsMenuId = 0x1010;
constexpr UINT_PTR kQuakeMenuId = 0x1020;

// WM_HOTKEY ids are a separate namespace from menu ids — no multiple-of-16
// constraint applies.
constexpr int kQuakeHotKeyId = 1;

// The title bar's native right-click/system menu has no Flutter-side
// equivalent, so this appends "Settings…", "Keyboard Shortcuts…" and "Quake
// Window" to it directly via Win32.
void AppendSettingsMenuItem(HWND hwnd) {
  HMENU menu = GetSystemMenu(hwnd, FALSE);
  if (!menu) return;
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kSettingsMenuId, L"Settings…");
  AppendMenu(menu, MF_STRING, kShortcutsMenuId, L"Keyboard Shortcuts…");
  AppendMenu(menu, MF_STRING, kQuakeMenuId, L"Quake Window");
}

// The work area of the display under the cursor, as an EncodableMap Dart's
// quakeFrame() can read directly — MONITORINFO is already top-left-origin,
// y growing downward, the same convention quake_geometry.dart works in, so
// unlike macOS this needs no flip.
flutter::EncodableValue CurrentScreenValue() {
  POINT cursor;
  GetCursorPos(&cursor);
  HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(MONITORINFO);
  GetMonitorInfo(monitor, &info);
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("x"),
       flutter::EncodableValue(static_cast<double>(info.rcWork.left))},
      {flutter::EncodableValue("y"),
       flutter::EncodableValue(static_cast<double>(info.rcWork.top))},
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(
           static_cast<double>(info.rcWork.right - info.rcWork.left))},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(
           static_cast<double>(info.rcWork.bottom - info.rcWork.top))},
  });
}

// Positions |hwnd| per the {x, y, width, height} map Dart's show() call
// carries, if present. A missing or malformed argument is a no-op — the
// window simply keeps whatever frame it already has.
void ApplyQuakeFrame(HWND hwnd, const flutter::EncodableValue* arguments) {
  if (!arguments) return;
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (!map) return;
  auto field = [map](const char* key) -> std::optional<double> {
    auto it = map->find(flutter::EncodableValue(key));
    if (it == map->end()) return std::nullopt;
    if (const auto* value = std::get_if<double>(&it->second)) return *value;
    return std::nullopt;
  };
  auto x = field("x");
  auto y = field("y");
  auto width = field("width");
  auto height = field("height");
  if (!x || !y || !width || !height) return;
  SetWindowPos(hwnd, nullptr, static_cast<int>(*x), static_cast<int>(*y),
               static_cast<int>(*width), static_cast<int>(*height),
               SWP_NOZORDER | SWP_NOACTIVATE);
}

// Drops the title bar and its buttons for the borderless look a drop-down
// terminal wants — WS_THICKFRAME stays, so edge-drag resizing still works.
// Mirrors `.titled` removal in MainFlutterWindow.swift.
void RemoveTitleBar(HWND hwnd) {
  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  style &= ~(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX);
  SetWindowLongPtr(hwnd, GWL_STYLE, style);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOACTIVATE);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project, bool quake)
    : project_(project), quake_(quake) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  if (quake_) {
    RemoveTitleBar(GetHandle());
  }

  AppendSettingsMenuItem(GetHandle());

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  system_menu_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "orthanc/system_menu",
          &flutter::StandardMethodCodec::GetInstance());

  if (quake_) {
    quake_channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            flutter_controller_->engine()->messenger(), "orthanc/quake",
            &flutter::StandardMethodCodec::GetInstance());
    quake_channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                   result) {
          HandleQuakeMethodCall(call, std::move(result));
        });
  }

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // The quake instance starts hidden — it must, for the eventual slide-down
  // animation to start from off-screen — and is shown only once Dart calls
  // back over |quake_channel_| after registering the hotkey.
  if (!quake_) {
    flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
    });
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (quake_) {
    UnregisterHotKey(GetHandle(), kQuakeHotKeyId);
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleQuakeMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "registerHotKey") {
    // A failed registration (another app already owns the chord) is
    // swallowed by design — the window stays reachable from the menu item
    // either way.
    RegisterHotKey(GetHandle(), kQuakeHotKeyId, MOD_CONTROL | MOD_NOREPEAT,
                    VK_OEM_3);
    result->Success();
    return;
  }
  if (call.method_name() == "currentScreen") {
    result->Success(CurrentScreenValue());
    return;
  }
  if (call.method_name() == "show") {
    ShowQuakeWindow(call.arguments());
    result->Success();
    return;
  }
  if (call.method_name() == "hide") {
    ShowWindow(GetHandle(), SW_MINIMIZE);
    result->Success();
    return;
  }
  result->NotImplemented();
}

void FlutterWindow::ShowQuakeWindow(const flutter::EncodableValue* arguments) {
  HWND hwnd = GetHandle();
  // Restored before repositioned: a minimized window's restore placement is
  // set unreliably if SetWindowPos runs first.
  ShowWindow(hwnd, SW_RESTORE);
  ApplyQuakeFrame(hwnd, arguments);
  // A background process asking for the foreground is subject to Windows'
  // foreground-lock. If the direct call is refused, briefly attaching this
  // thread's input queue to the current foreground window's is the standard
  // workaround.
  if (!SetForegroundWindow(hwnd)) {
    DWORD foreground_thread =
        GetWindowThreadProcessId(GetForegroundWindow(), nullptr);
    DWORD this_thread = GetCurrentThreadId();
    AttachThreadInput(foreground_thread, this_thread, TRUE);
    SetForegroundWindow(hwnd);
    AttachThreadInput(foreground_thread, this_thread, FALSE);
  }
  if (flutter_controller_) {
    SetFocus(flutter_controller_->view()->GetNativeWindow());
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SYSCOMMAND:
      if ((wparam & 0xFFF0) == kSettingsMenuId && system_menu_channel_) {
        system_menu_channel_->InvokeMethod("openSettings", nullptr);
        return 0;
      }
      if ((wparam & 0xFFF0) == kShortcutsMenuId && system_menu_channel_) {
        system_menu_channel_->InvokeMethod("openShortcuts", nullptr);
        return 0;
      }
      if ((wparam & 0xFFF0) == kQuakeMenuId && system_menu_channel_) {
        system_menu_channel_->InvokeMethod("openQuake", nullptr);
        return 0;
      }
      break;
    case WM_HOTKEY:
      if (wparam == kQuakeHotKeyId && quake_channel_) {
        bool visible = !IsIconic(hwnd);
        quake_channel_->InvokeMethod(
            "toggle",
            std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                {flutter::EncodableValue("visible"),
                 flutter::EncodableValue(visible)}}));
        return 0;
      }
      break;
    case WM_EXITSIZEMOVE:
      // Fires once, at the end of a user's resize-or-move drag — never for a
      // programmatic SetWindowPos (that never enters the size-move loop), so
      // ShowQuakeWindow's own frame changes can never be mistaken for this.
      // A pure move re-reports the unchanged width/height below, which is
      // harmless to persist again.
      if (quake_ && quake_channel_) {
        RECT rect;
        GetWindowRect(hwnd, &rect);
        quake_channel_->InvokeMethod(
            "resized",
            std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                {flutter::EncodableValue("width"),
                 flutter::EncodableValue(
                     static_cast<double>(rect.right - rect.left))},
                {flutter::EncodableValue("height"),
                 flutter::EncodableValue(
                     static_cast<double>(rect.bottom - rect.top))}}));
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

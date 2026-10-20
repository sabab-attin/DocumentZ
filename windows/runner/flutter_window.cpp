#include "flutter_window.h"

#include <optional>
#include <filesystem>
#include <vector>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>
#include "utils.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

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
  documents_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "documentz/documents",
      &flutter::StandardMethodCodec::GetInstance());
  documents_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "takeDocument") {
      if (pending_documents_.empty()) { result->Success(); return; }
      auto document = std::move(pending_documents_.front());
      pending_documents_.pop_front();
      result->Success(flutter::EncodableValue(document));
    } else if (call.method_name() == "finishDocument") {
      // Unlike Android's temporary staging copy, Windows owns no source files.
      result->Success();
    } else { result->NotImplemented(); }
  });
  appearance_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "documentz/appearance",
      &flutter::StandardMethodCodec::GetInstance());
  appearance_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "fullscreen") { result->NotImplemented(); return; }
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!arguments) { result->Error("invalid_argument", "Expected enabled flag."); return; }
    const auto enabled = arguments->find(flutter::EncodableValue("enabled"));
    if (enabled == arguments->end() || !std::holds_alternative<bool>(enabled->second)) {
      result->Error("invalid_argument", "Expected enabled flag."); return;
    }
    SetFullscreen(std::get<bool>(enabled->second));
    result->Success();
  });
  QueueCommandLine(::GetCommandLineW());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  documents_channel_.reset();
  appearance_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_GETMINMAXINFO) {
    auto* bounds = reinterpret_cast<MINMAXINFO*>(lparam);
    const UINT dpi = ::GetDpiForWindow(hwnd);
    bounds->ptMinTrackSize.x = ::MulDiv(480, static_cast<int>(dpi), 96);
    bounds->ptMinTrackSize.y = ::MulDiv(360, static_cast<int>(dpi), 96);
    return 0;
  }
  if (message == WM_COPYDATA) {
    const auto* packet = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (!packet || packet->dwData != 0x445A4F50 || !packet->lpData ||
        packet->cbData < sizeof(wchar_t) || packet->cbData > 65536 ||
        packet->cbData % sizeof(wchar_t) != 0) return FALSE;
    const auto* text = static_cast<const wchar_t*>(packet->lpData);
    if (text[packet->cbData / sizeof(wchar_t) - 1] != L'\0') return FALSE;
    try { return QueueCommandLine(text) ? TRUE : FALSE; }
    catch (...) { return FALSE; }
  }
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

bool FlutterWindow::QueueCommandLine(const wchar_t* command_line) {
  int count = 0;
  wchar_t** arguments = ::CommandLineToArgvW(command_line, &count);
  if (!arguments) return false;
  // Copy first: WM_COPYDATA's buffer belongs to the sender.
  std::vector<std::wstring> paths;
  for (int i = 1; i < count; ++i) paths.emplace_back(arguments[i]);
  ::LocalFree(arguments);
  if (pending_documents_.size() + paths.size() > 256) return false;
  using flutter::EncodableValue;
  for (const auto& path : paths) {
    if (!std::filesystem::path(path).is_absolute()) continue;
    const DWORD attributes = ::GetFileAttributesW(path.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
    const auto name = std::filesystem::path(path).filename().wstring();
    pending_documents_.push_back(flutter::EncodableMap{
      {EncodableValue("id"), EncodableValue(std::to_string(++next_document_id_))},
      {EncodableValue("name"), EncodableValue(Utf8FromUtf16(name.c_str()))},
      {EncodableValue("path"), EncodableValue(Utf8FromUtf16(path.c_str()))},
    });
  }
  if (documents_channel_ && !pending_documents_.empty()) {
    documents_channel_->InvokeMethod("documentAvailable", std::make_unique<EncodableValue>());
  }
  return true;
}

void FlutterWindow::SetFullscreen(bool enabled) {
  if (enabled == fullscreen_) return;
  HWND window = GetHandle();
  if (enabled) {
    normal_style_ = ::GetWindowLongPtr(window, GWL_STYLE);
    normal_placement_.length = sizeof(WINDOWPLACEMENT);
    ::GetWindowPlacement(window, &normal_placement_);
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(MONITORINFO);
    if (!::GetMonitorInfo(::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) return;
    ::SetWindowLongPtr(window, GWL_STYLE, normal_style_ & ~WS_OVERLAPPEDWINDOW);
    ::SetWindowPos(window, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
        monitor.rcMonitor.right - monitor.rcMonitor.left,
        monitor.rcMonitor.bottom - monitor.rcMonitor.top, SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
  } else {
    ::SetWindowLongPtr(window, GWL_STYLE, normal_style_);
    ::SetWindowPlacement(window, &normal_placement_);
    ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  }
  fullscreen_ = enabled;
}

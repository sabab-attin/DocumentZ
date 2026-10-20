#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <deque>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  bool QueueCommandLine(const wchar_t* command_line);
  void SetFullscreen(bool enabled);
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> documents_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> appearance_channel_;
  std::deque<flutter::EncodableMap> pending_documents_;
  int64_t next_document_id_ = 0;
  bool fullscreen_ = false;
  LONG_PTR normal_style_ = 0;
  WINDOWPLACEMENT normal_placement_{};

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

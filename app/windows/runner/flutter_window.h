#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

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
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // "gatex/app": forwards a second launch's command line to Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> app_channel_;
};

// Tag of the WM_COPYDATA message a second launch sends to this window.
constexpr ULONG_PTR kActivateMessage = 0x47415458;  // "GATX"

// Window class and title main.cpp looks up to find the running copy.
constexpr const wchar_t kWindowTitle[] = L"GateX VPN";

#endif  // RUNNER_FLUTTER_WINDOW_H_

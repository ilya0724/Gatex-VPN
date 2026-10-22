#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // One copy at a time: a second launch (a gatex:// link, the Start menu)
  // hands its command line to the running window and exits.
  HANDLE single = ::CreateMutexW(nullptr, TRUE, L"Local\\GateX.VPN.SingleInstance");
  if (single && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND running = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle);
    if (running) {
      std::wstring line = command_line ? command_line : L"";
      COPYDATASTRUCT data{kActivateMessage,
                          static_cast<DWORD>((line.size() + 1) * sizeof(wchar_t)),
                          const_cast<wchar_t*>(line.c_str())};
      DWORD pid = 0;
      ::GetWindowThreadProcessId(running, &pid);
      ::AllowSetForegroundWindow(pid);
      ::SendMessageTimeoutW(running, WM_COPYDATA, 0,
                            reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG,
                            3000, nullptr);
    }
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(460, 820);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

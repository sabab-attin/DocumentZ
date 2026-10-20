#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Keep one process per user session; Explorer forwards files to its queue.
  HANDLE instance_mutex = ::CreateMutexW(nullptr, TRUE, L"Local\\DocumentZ.Desktop.Instance.v1");
  if (!instance_mutex) return EXIT_FAILURE;
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = nullptr;
    for (int attempt = 0; attempt < 100 && !existing; ++attempt) {
      existing = ::FindWindowW(L"DocumentZ.Desktop.Window.v1", L"DocumentZ");
      if (!existing) ::Sleep(50);
    }
    bool forwarded = false;
    if (existing) {
      const wchar_t* arguments = ::GetCommandLineW();
      COPYDATASTRUCT packet{};
      packet.dwData = 0x445A4F50;
      packet.cbData = static_cast<DWORD>((wcslen(arguments) + 1) * sizeof(wchar_t));
      packet.lpData = const_cast<wchar_t*>(arguments);
      DWORD_PTR accepted = 0;
      forwarded = ::SendMessageTimeoutW(existing, WM_COPYDATA, 0,
          reinterpret_cast<LPARAM>(&packet), SMTO_ABORTIFHUNG | SMTO_BLOCK,
          5000, &accepted) != 0 && accepted != 0;
      if (forwarded) {
        if (::IsIconic(existing)) ::ShowWindow(existing, SW_RESTORE);
        ::SetForegroundWindow(existing);
      }
    }
    ::CloseHandle(instance_mutex);
    if (!forwarded) {
      ::MessageBoxW(nullptr, L"DocumentZ is still starting or not responding. Try opening the file again.",
                    L"DocumentZ", MB_OK | MB_ICONINFORMATION);
    }
    return forwarded ? EXIT_SUCCESS : EXIT_FAILURE;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
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
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"DocumentZ", origin, size)) {
    ::CloseHandle(instance_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::ReleaseMutex(instance_mutex);
  ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}

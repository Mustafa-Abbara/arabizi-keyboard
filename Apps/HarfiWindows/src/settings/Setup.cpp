// "Install Harfi.exe": the installer a person double-clicks, in the folder extracted from Harfi-Windows-x64.zip. It
// runs install.ps1 from its own folder (no PowerShell window, no execution-policy question), shows what it is doing
// and how far the model download is, then says how to turn the keyboard on and opens the Harfi window on Welcome.
// install.ps1 stays the one place that knows how to install; this only puts a window on it.
//
//   "Install Harfi.exe"
//   "Install Harfi.exe" --render FILE.png [--state intro|installing|done|failed]   a picture of the window, and exit
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <atomic>
#include <string>
#include <vector>
#include "Ui.h"

HINSTANCE g_module = nullptr;
std::atomic<long> g_objects{0};

std::wstring ModuleFolder() {
    wchar_t path[MAX_PATH] = {};
    DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring folder(path, length);
    size_t slash = folder.find_last_of(L'\\');
    return slash == std::wstring::npos ? L"." : folder.substr(0, slash);
}

void DebugLog(const char *) {}

namespace {
const wchar_t *ClassName = L"HarfiSetupWindow";
const int Width = 520, Height = 360;  // at 96 DPI
const UINT LineMessage = WM_APP + 1;      // lParam: a std::wstring* the script printed
const UINT FinishedMessage = WM_APP + 2;  // wParam: the script's exit code
const UINT_PTR ProgressTimer = 1;

enum class State { Intro, Installing, Done, Failed };
enum class Action { Install, Language, Open, Close };

struct Target {
    Gdiplus::RectF box;
    Action action;
};

std::wstring Installed() {
    wchar_t local[MAX_PATH] = {};
    GetEnvironmentVariableW(L"LOCALAPPDATA", local, MAX_PATH);
    return std::wstring(local) + L"\\Harfi";
}

// The bytes in a folder's files (the model's parts while they download).
unsigned long long FolderSize(const std::wstring &folder) {
    WIN32_FIND_DATAW found;
    HANDLE search = FindFirstFileW((folder + L"\\*").c_str(), &found);
    if (search == INVALID_HANDLE_VALUE) return 0;
    unsigned long long total = 0;
    do {
        if (!(found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
            total += (static_cast<unsigned long long>(found.nFileSizeHigh) << 32) | found.nFileSizeLow;
        }
    } while (FindNextFileW(search, &found));
    FindClose(search);
    return total;
}

class Setup {
public:
    State state = State::Intro;
    std::wstring status = L"Getting ready\x2026";
    std::vector<std::wstring> lines;  // what the script said last, for when it fails
    unsigned long long modelBytes = 0;  // the size of the model being downloaded, 0 when none is
    float progress = 0;                 // of the download, 0 to 1
    bool on = false;                    // install.ps1 added Harfi to the keyboards itself
    float scale = 1;

    void Draw(Gdiplus::Graphics &graphics, SIZE size) {
        Palette colours = Colours();
        graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
        graphics.Clear(Colour(colours.surface));
        targets.clear();
        const float left = S(28), width = static_cast<float>(size.cx) - 2 * left;
        Gdiplus::Font title(LatinFamily(), S(22), Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
        Gdiplus::Font strong(LatinFamily(), S(15), 0, Gdiplus::UnitPixel);
        Gdiplus::Font body(LatinFamily(), S(13), 0, Gdiplus::UnitPixel);
        Gdiplus::Font arabic(ArabicFamily(), S(17), 0, Gdiplus::UnitPixel);
        WrappedText(graphics, L"Harfi", title, colours.text, left, S(22), width);
        Write(graphics, L"\x062D\x0631\x0641\x064A", arabic, colours.muted,
              Gdiplus::RectF(left + width - S(60), S(24), S(60), S(28)), true);

        const float pad = S(16), top = S(70);
        Gdiplus::RectF card(left, top, width, static_cast<float>(size.cy) - top - S(76));
        FillBox(graphics, card, S(10), colours.chip, colours.border);
        float x = card.X + pad, y = card.Y + pad, w = card.Width - 2 * pad;
        auto heading = [&](const std::wstring &text) { y += WrappedText(graphics, text, strong, colours.text, x, y, w) + S(6); };
        auto paragraph = [&](const std::wstring &text, COLORREF colour) {
            y += WrappedText(graphics, text, body, colour, x, y, w) + S(8);
        };
        const float buttons = static_cast<float>(size.cy) - S(54);
        float right = left + width;
        auto button = [&](const std::wstring &label, Action action, bool quiet) {
            float bw = Measure(label, body, false).Width + S(28), bh = S(32);
            Gdiplus::RectF box(right - bw, buttons, bw, bh);
            FillBox(graphics, box, S(8), quiet ? colours.surface : colours.accent, quiet ? colours.border : CLR_INVALID);
            Write(graphics, label, body, quiet ? colours.text : colours.onAccent, box, false);
            targets.push_back({box, action});
            right -= bw + S(8);
        };

        switch (state) {
            case State::Intro:
                heading(L"Type Arabizi, get Arabic");
                paragraph(L"This puts the Harfi keyboard on this PC, for your account only. It converts what you "
                          L"type on this PC; nothing you type is sent anywhere.", colours.muted);
                paragraph(L"The first time, it downloads the conversion model (about 800 MB), so it can take a few "
                          L"minutes. Windows may ask once for permission to add the keyboard.", colours.muted);
                button(L"Install", Action::Install, false);
                button(L"Cancel", Action::Close, true);
                break;
            case State::Installing: {
                heading(L"Installing\x2026");
                paragraph(status, colours.muted);
                if (modelBytes > 0) {
                    Gdiplus::RectF track(x, y + S(6), w, S(8));
                    FillBox(graphics, track, S(4), colours.accentSoft);
                    Gdiplus::RectF done = track;
                    done.Width = (std::max)(track.Height, track.Width * progress);
                    FillBox(graphics, done, S(4), colours.accent);
                    y += S(26);
                    std::wstring amount = std::to_wstring(static_cast<int>(progress * static_cast<float>(modelBytes) / 1048576)) +
                                          L" of " + std::to_wstring(static_cast<int>(modelBytes / 1048576)) + L" MB";
                    paragraph(amount, colours.muted);
                    paragraph(L"If the connection drops, run this again: the download carries on where it stopped.",
                              colours.muted);
                }
                break;
            }
            case State::Done:
                if (on) {
                    heading(L"Harfi is on");
                    paragraph(L"Switch to it with Win+Space in any app, type Arabizi and press Enter.", colours.text);
                    paragraph(L"It is in your keyboards under Arabic (Lebanon).", colours.muted);
                    button(L"Show me how to use it", Action::Open, false);
                    break;
                }
                heading(L"Harfi is installed");
                paragraph(L"Turn it on once, in Windows' language settings:", colours.text);
                paragraph(L"Arabic (Lebanon)  \x2192  Language options  \x2192  Add a keyboard  \x2192  Harfi\n"
                          L"(Add the Arabic (Lebanon) language first if it is not listed.)", colours.muted);
                paragraph(L"Then switch to it with Win+Space in any app.", colours.text);
                button(L"Show me how to use it", Action::Open, false);
                button(L"Open language settings", Action::Language, true);
                break;
            case State::Failed: {
                heading(L"Harfi could not be installed");
                std::wstring said;
                for (const std::wstring &line : lines) said += line + L"\n";
                paragraph(said.empty() ? L"The installer stopped without saying why." : said, colours.muted);
                button(L"Try again", Action::Install, false);
                button(L"Close", Action::Close, true);
                break;
            }
        }
    }

    const Target *At(POINT point) const {
        Gdiplus::PointF at(static_cast<float>(point.x), static_cast<float>(point.y));
        for (const Target &target : targets) {
            if (target.box.Contains(at)) return &target;
        }
        return nullptr;
    }

    // A line the script printed: its messages become the status; curl's progress table is skipped.
    void Said(const std::wstring &line) {
        size_t first = line.find_first_not_of(L" \t");
        if (first == std::wstring::npos) return;
        wchar_t start = line[first];
        if ((start >= L'0' && start <= L'9') || start == L'%' || line.find(L"Dload") != std::wstring::npos) return;
        status = line.substr(first);
        if (status.rfind(L"Harfi is on", 0) == 0) on = true;
        lines.push_back(status);
        if (lines.size() > 4) lines.erase(lines.begin());
        size_t mb = line.find(L" MB, once");  // "Downloading the conversion model (770 MB, once)..."
        size_t open = line.rfind(L'(', mb);
        if (mb != std::wstring::npos && open != std::wstring::npos) {
            modelBytes = static_cast<unsigned long long>(_wtoi(line.substr(open + 1).c_str())) * 1048576;
        }
    }

    void Poll() {
        if (modelBytes == 0) return;
        progress = (std::min)(1.0f, static_cast<float>(FolderSize(Installed() + L"\\models\\download")) /
                                        static_cast<float>(modelBytes));
    }

private:
    float S(float value) const { return value * scale; }
    std::vector<Target> targets;
};

Setup setup;

// Runs install.ps1 hidden and sends each line it prints to the window, then its exit code.
DWORD WINAPI Run(LPVOID parameter) {
    HWND hwnd = static_cast<HWND>(parameter);
    SECURITY_ATTRIBUTES inherit = {sizeof(inherit), nullptr, TRUE};
    HANDLE read = nullptr, write = nullptr;
    DWORD code = 1;
    if (CreatePipe(&read, &write, &inherit, 0)) {
        SetHandleInformation(read, HANDLE_FLAG_INHERIT, 0);
        std::wstring command = L"powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" +
                               ModuleFolder() + L"\\install.ps1\"";
        STARTUPINFOW startup = {sizeof(startup)};
        startup.dwFlags = STARTF_USESTDHANDLES;
        startup.hStdOutput = write;
        startup.hStdError = write;
        PROCESS_INFORMATION process = {};
        if (CreateProcessW(nullptr, command.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr,
                           ModuleFolder().c_str(), &startup, &process)) {
            CloseHandle(write);
            write = nullptr;
            std::string pending;
            char buffer[4096];
            DWORD got = 0;
            while (ReadFile(read, buffer, sizeof(buffer), &got, nullptr) && got > 0) {
                pending.append(buffer, got);
                size_t end;
                while ((end = pending.find_first_of("\r\n")) != std::string::npos) {
                    if (end > 0) PostMessageW(hwnd, LineMessage, 0, reinterpret_cast<LPARAM>(new std::wstring(Wide(pending.substr(0, end)))));
                    pending.erase(0, end + 1);
                }
            }
            WaitForSingleObject(process.hProcess, INFINITE);
            GetExitCodeProcess(process.hProcess, &code);
            CloseHandle(process.hThread);
            CloseHandle(process.hProcess);
        }
        if (write) CloseHandle(write);
        CloseHandle(read);
    }
    PostMessageW(hwnd, FinishedMessage, code, 0);
    return 0;
}

void Do(HWND hwnd, Action action) {
    switch (action) {
        case Action::Install:
            setup.state = State::Installing;
            setup.status = L"Getting ready\x2026";
            setup.lines.clear();
            setup.modelBytes = 0;
            setup.progress = 0;
            setup.on = false;
            SetTimer(hwnd, ProgressTimer, 500, nullptr);
            CloseHandle(CreateThread(nullptr, 0, Run, hwnd, 0, nullptr));
            break;
        case Action::Language:
            ShellExecuteW(hwnd, L"open", L"ms-settings:regionlanguage", nullptr, nullptr, SW_SHOWNORMAL);
            break;
        case Action::Open:
            ShellExecuteW(hwnd, L"open", (Installed() + L"\\harfi-settings.exe").c_str(), L"--welcome", nullptr,
                          SW_SHOWNORMAL);
            DestroyWindow(hwnd);
            return;
        case Action::Close: DestroyWindow(hwnd); return;
    }
    InvalidateRect(hwnd, nullptr, FALSE);
}

LRESULT CALLBACK Procedure(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
        case WM_PAINT:
            PaintBuffered(hwnd, [](Gdiplus::Graphics &graphics, SIZE size) { setup.Draw(graphics, size); });
            return 0;
        case WM_ERASEBKGND: return 1;
        case LineMessage: {
            auto *line = reinterpret_cast<std::wstring *>(lParam);
            setup.Said(*line);
            delete line;
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        }
        case FinishedMessage:
            KillTimer(hwnd, ProgressTimer);
            setup.state = wParam == 0 ? State::Done : State::Failed;
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        case WM_TIMER:
            setup.Poll();
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        case WM_LBUTTONUP: {
            POINT at = {GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
            if (const Target *target = setup.At(at)) Do(hwnd, target->action);
            return 0;
        }
        case WM_SETCURSOR:
            if (LOWORD(lParam) == HTCLIENT) {
                POINT at;
                GetCursorPos(&at);
                ScreenToClient(hwnd, &at);
                SetCursor(LoadCursorW(nullptr, setup.At(at) ? IDC_HAND : IDC_ARROW));
                return TRUE;
            }
            break;
        case WM_KEYDOWN:
            if (wParam == VK_RETURN) {  // Enter: the main button of each step
                if (setup.state == State::Intro || setup.state == State::Failed) Do(hwnd, Action::Install);
                else if (setup.state == State::Done) Do(hwnd, Action::Open);
                return 0;
            }
            if (wParam == VK_ESCAPE && setup.state != State::Installing) {
                DestroyWindow(hwnd);
                return 0;
            }
            break;
        case WM_CLOSE:
            if (setup.state == State::Installing) return 0;  // the script is still copying or registering
            break;
        case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}
}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    g_module = instance;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    int count = 0;
    wchar_t **arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    std::wstring render;
    for (int i = 1; arguments && i < count; ++i) {
        std::wstring argument = arguments[i];
        if (argument == L"--render" && i + 1 < count) render = arguments[++i];
        if (argument == L"--state" && i + 1 < count) {
            std::wstring name = arguments[++i];
            setup.state = name == L"installing" ? State::Installing : name == L"done" ? State::Done
                        : name == L"failed" ? State::Failed : State::Intro;
        }
    }
    LatinFamily();  // starts GDI+

    if (!render.empty()) {
        setup.scale = 1.5f;
        if (setup.state == State::Installing) {
            setup.Said(L"Downloading the conversion model (770 MB, once)...");
            setup.progress = 0.42f;
        }
        if (setup.state == State::Done) setup.Said(L"Harfi is on: switch to it with Win+Space.");
        if (setup.state == State::Failed) setup.Said(L"Downloading Llama-3.2-1B-Harfi-v3-Q4_K_M.gguf.part03 failed. Run install.ps1 again to resume.");
        SIZE size = {static_cast<LONG>(Width * setup.scale), static_cast<LONG>(Height * setup.scale)};
        Gdiplus::Bitmap bitmap(size.cx, size.cy, PixelFormat32bppARGB);
        Gdiplus::Graphics graphics(&bitmap);
        setup.Draw(graphics, size);
        return SavePng(bitmap, render) ? 0 : 1;
    }

    if (HWND open = FindWindowW(ClassName, nullptr)) {
        SetForegroundWindow(open);
        return 0;
    }
    WNDCLASSEXW type = {sizeof(type)};
    type.lpfnWndProc = Procedure;
    type.hInstance = instance;
    type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    type.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(1));  // harfi.rc
    type.hIconSm = type.hIcon;
    type.lpszClassName = ClassName;
    RegisterClassExW(&type);
    const DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    UINT dpi = GetDpiForSystem();
    setup.scale = static_cast<float>(dpi) / 96;
    RECT frame = {0, 0, MulDiv(Width, static_cast<int>(dpi), 96), MulDiv(Height, static_cast<int>(dpi), 96)};
    AdjustWindowRectExForDpi(&frame, style, FALSE, 0, dpi);
    int w = frame.right - frame.left, h = frame.bottom - frame.top;
    HWND hwnd = CreateWindowExW(0, ClassName, L"Install Harfi", style, (GetSystemMetrics(SM_CXSCREEN) - w) / 2,
                                (GetSystemMetrics(SM_CYSCREEN) - h) / 2, w, h, nullptr, nullptr, instance, nullptr);
    if (!hwnd) return 1;
    ShowWindow(hwnd, show);
    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return 0;
}

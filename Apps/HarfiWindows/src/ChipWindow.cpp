#include "ChipWindow.h"

namespace {
const wchar_t ClassName[] = L"HarfiChips";

struct Palette {
    COLORREF surface, text, muted, border, accent, accentSoft;
};

// Cedar and sand (design/palette.json).
Palette Colours() {
    DWORD light = 1, size = sizeof(light);
    RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                 L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size);
    if (light) return {RGB(0xFF, 0xFF, 0xFF), RGB(0x1E, 0x2A, 0x25), RGB(0x6B, 0x75, 0x6F), RGB(0xE4, 0xDF, 0xD4),
                       RGB(0x2F, 0x6B, 0x5A), RGB(0xE2, 0xEE, 0xE8)};
    return {RGB(0x1D, 0x25, 0x22), RGB(0xE9, 0xEE, 0xEB), RGB(0x93, 0xA0, 0x99), RGB(0x2C, 0x36, 0x32),
            RGB(0x7D, 0xBB, 0xA5), RGB(0x21, 0x39, 0x2F)};
}

// Latin labels ("Spell it", the spelling hint) use the Latin font; spellings and the word use the Arabic one.
bool IsLatin(const std::wstring &label) { return label == L"Spell it" || label.rfind(L"Tab", 0) == 0; }

int Scaled(int value) { return MulDiv(value, static_cast<int>(GetDpiForSystem()), 96); }

const int Gap = 6, PadX = 10, PadY = 4, Margin = 6, MinHeight = 32;
}  // namespace

ChipWindow::~ChipWindow() {
    if (window_) DestroyWindow(window_);
    if (arabic_) DeleteObject(arabic_);
    if (latin_) DeleteObject(latin_);
}

void ChipWindow::Show(const Effect &effect, const RECT &text, Pick pick, SpellIt spellIt) {
    pick_ = std::move(pick);
    spellIt_ = std::move(spellIt);
    if (!window_) {
        WNDCLASSEXW type = {sizeof(type)};
        type.lpfnWndProc = Procedure;
        type.hInstance = g_module;
        type.hCursor = LoadCursorW(nullptr, IDC_HAND);
        type.lpszClassName = ClassName;
        RegisterClassExW(&type);  // fails harmlessly when already registered by another instance
        window_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, ClassName, L"", WS_POPUP,
                                  0, 0, 0, 0, nullptr, nullptr, g_module, this);
        // The Arabic font Harfi uses everywhere, from its own folder, for this process only.
        AddFontResourceExW((ModuleFolder() + L"\\fonts\\NotoNaskhArabic-Variable.ttf").c_str(), FR_PRIVATE, nullptr);
        arabic_ = CreateFontW(-Scaled(20), 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0,
                              L"Noto Naskh Arabic");
        latin_ = CreateFontW(-Scaled(13), 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0,
                             L"Segoe UI");
    }
    if (!window_) return;

    chips_.clear();
    if (!effect.word.empty() && !effect.spelling) chips_.push_back({effect.word + L"  ←", L"", false, false, true});
    for (size_t i = 0; i < effect.candidates.size(); ++i) {
        std::wstring label = effect.candidates[i];
        if (!effect.spelling && i < 9) label = std::to_wstring(i + 1) + L"  " + label;
        chips_.push_back({label, effect.candidates[i], !effect.spelling && i < 9,
                          static_cast<int>(i) == effect.choice, false});
    }
    chips_.push_back(effect.spelling ? Chip{L"Tab changes it · Enter takes it", L"", false, false, true}
                                     : Chip{L"Spell it", L"\x01spell", false, false, true});

    HDC dc = GetDC(window_);
    Layout(dc);
    ReleaseDC(window_, dc);

    // Above the text, where the Mac keyboard puts its preview; below it when there is no room at the top.
    HMONITOR monitor = MonitorFromRect(&text, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {sizeof(info)};
    GetMonitorInfoW(monitor, &info);
    int x = text.left, y = text.top - size_.cy - Scaled(Gap);
    if (y < info.rcWork.top) y = text.bottom + Scaled(Gap);
    if (x + size_.cx > info.rcWork.right) x = info.rcWork.right - size_.cx - Scaled(4);
    if (x < info.rcWork.left) x = info.rcWork.left + Scaled(4);
    SetWindowPos(window_, HWND_TOPMOST, x, y, size_.cx, size_.cy, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    HRGN shape = CreateRoundRectRgn(0, 0, size_.cx + 1, size_.cy + 1, Scaled(12), Scaled(12));
    SetWindowRgn(window_, shape, TRUE);  // the window owns the region from here
    InvalidateRect(window_, nullptr, TRUE);
}

void ChipWindow::Hide() {
    if (window_) ShowWindow(window_, SW_HIDE);
}

// Right to left, as Arabic reads: the first chip (the word being fixed) on the right.
void ChipWindow::Layout(HDC dc) {
    int x = Scaled(Margin), height = Scaled(MinHeight);
    std::vector<SIZE> sizes;
    for (const Chip &chip : chips_) {
        SelectObject(dc, IsLatin(chip.label) ? latin_ : arabic_);
        SIZE text = {};
        GetTextExtentPoint32W(dc, chip.label.c_str(), static_cast<int>(chip.label.size()), &text);
        SIZE box = {text.cx + 2 * Scaled(PadX), max(text.cy + 2 * Scaled(PadY), height)};
        sizes.push_back(box);
        x += box.cx + Scaled(Gap);
    }
    size_ = {x - Scaled(Gap) + Scaled(Margin), height + 2 * Scaled(Margin)};
    int right = size_.cx - Scaled(Margin);
    for (size_t i = 0; i < chips_.size(); ++i) {
        chips_[i].box = {right - sizes[i].cx, Scaled(Margin), right, Scaled(Margin) + height};
        right -= sizes[i].cx + Scaled(Gap);
    }
}

void ChipWindow::Paint(HDC dc) {
    Palette colours = Colours();
    RECT all = {0, 0, size_.cx, size_.cy};
    HBRUSH surface = CreateSolidBrush(colours.surface);
    FillRect(dc, &all, surface);
    DeleteObject(surface);
    SetBkMode(dc, TRANSPARENT);
    for (const Chip &chip : chips_) {
        bool framed = !(chip.quiet && chip.value.empty());
        if (framed) {
            HBRUSH fill = CreateSolidBrush(chip.selected ? colours.accentSoft : colours.surface);
            HPEN pen = CreatePen(PS_SOLID, Scaled(1), chip.selected ? colours.accent : colours.border);
            HGDIOBJ oldBrush = SelectObject(dc, fill), oldPen = SelectObject(dc, pen);
            RoundRect(dc, chip.box.left, chip.box.top, chip.box.right, chip.box.bottom, Scaled(8), Scaled(8));
            SelectObject(dc, oldBrush);
            SelectObject(dc, oldPen);
            DeleteObject(fill);
            DeleteObject(pen);
        }
        SelectObject(dc, IsLatin(chip.label) ? latin_ : arabic_);
        SetTextColor(dc, chip.selected ? colours.accent : (chip.quiet ? colours.muted : colours.text));
        RECT box = chip.box;
        DrawTextW(dc, chip.label.c_str(), static_cast<int>(chip.label.size()), &box,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }
}

void ChipWindow::Click(POINT at) {
    for (const Chip &chip : chips_) {
        if (chip.value.empty() || !PtInRect(&chip.box, at)) continue;
        if (chip.value == L"\x01spell") { if (spellIt_) spellIt_(); }
        else if (pick_) { pick_(chip.value); }
        return;
    }
}

LRESULT CALLBACK ChipWindow::Procedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_NCCREATE) {
        auto *create = reinterpret_cast<CREATESTRUCTW *>(lParam);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto *self = reinterpret_cast<ChipWindow *>(GetWindowLongPtrW(window, GWLP_USERDATA));
    switch (message) {
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;  // a click never takes the focus from the app being typed in
        case WM_LBUTTONDOWN:
            if (self) self->Click({static_cast<short>(LOWORD(lParam)), static_cast<short>(HIWORD(lParam))});
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT paint;
            HDC dc = BeginPaint(window, &paint);
            if (self) self->Paint(dc);
            EndPaint(window, &paint);
            return 0;
        }
        default:
            return DefWindowProcW(window, message, wParam, lParam);
    }
}

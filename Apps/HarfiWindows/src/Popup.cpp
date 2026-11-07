#include "Popup.h"
#include <windowsx.h>

namespace {
const UINT_PTR AnimationTimer = 100;
const ULONGLONG FadeIn = 180, FadeOut = 120;  // ms: the Mac's chips rise and fade in over 0.18 s, eased out

// GDI+ for this process, started on first use (never in DllMain) and kept: the keyboard is never unloaded.
void StartGdiplus() {
    static ULONG_PTR token = [] {
        ULONG_PTR started = 0;
        Gdiplus::GdiplusStartupInput input;
        Gdiplus::GdiplusStartup(&started, &input, nullptr);
        return started;
    }();
    (void)token;
}

float EaseOut(float t) { return 1 - (1 - t) * (1 - t) * (1 - t); }
}  // namespace

Gdiplus::FontFamily *ArabicFamily() {
    StartGdiplus();
    static Gdiplus::FontFamily *family = []() -> Gdiplus::FontFamily * {
        auto *fonts = new Gdiplus::PrivateFontCollection();  // kept for the life of the process, like the family
        fonts->AddFontFile((ModuleFolder() + L"\\fonts\\NotoNaskhArabic-Variable.ttf").c_str());
        auto *found = new Gdiplus::FontFamily();
        INT count = 0;
        if (fonts->GetFamilyCount() > 0 && fonts->GetFamilies(1, found, &count) == Gdiplus::Ok && count == 1) {
            return found;
        }
        delete found;
        return new Gdiplus::FontFamily(L"Segoe UI");  // has Arabic too, if the font file is missing
    }();
    return family;
}

Gdiplus::FontFamily *LatinFamily() {
    StartGdiplus();
    static Gdiplus::FontFamily *family = new Gdiplus::FontFamily(L"Segoe UI");
    return family;
}

namespace {
// Tight, unwrapped and centred text (GDI+ formats cannot be copied, so they are set up in place).
void Configure(Gdiplus::StringFormat &format, bool rtl) {
    // Without LineLimit (part of GenericTypographic): it drops a line whose box is a rounding error too short.
    INT flags = (format.GetFormatFlags() & ~Gdiplus::StringFormatFlagsLineLimit) |
                Gdiplus::StringFormatFlagsMeasureTrailingSpaces | Gdiplus::StringFormatFlagsNoWrap;
    if (rtl) flags |= Gdiplus::StringFormatFlagsDirectionRightToLeft;
    format.SetFormatFlags(flags);
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
}
}  // namespace

Gdiplus::SizeF Measure(const std::wstring &text, const Gdiplus::Font &font, bool rtl) {
    Gdiplus::Bitmap one(1, 1, PixelFormat32bppPARGB);
    Gdiplus::Graphics graphics(&one);
    graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
    Gdiplus::StringFormat format(Gdiplus::StringFormat::GenericTypographic());
    Configure(format, rtl);
    Gdiplus::RectF box;
    graphics.MeasureString(text.c_str(), static_cast<INT>(text.size()), &font, Gdiplus::PointF(0, 0), &format, &box);
    return {box.Width, box.Height};
}

void Write(Gdiplus::Graphics &graphics, const std::wstring &text, const Gdiplus::Font &font, COLORREF colour,
           const Gdiplus::RectF &box, bool rtl) {
    Gdiplus::StringFormat format(Gdiplus::StringFormat::GenericTypographic());
    Configure(format, rtl);
    Gdiplus::SolidBrush brush(Colour(colour));
    graphics.DrawString(text.c_str(), static_cast<INT>(text.size()), &font, box, &format, &brush);
}

void RoundedRect(Gdiplus::GraphicsPath &path, const Gdiplus::RectF &rect, float radius) {
    float d = radius * 2;
    if (d > rect.Height) d = rect.Height;
    if (d > rect.Width) d = rect.Width;
    path.AddArc(rect.X, rect.Y, d, d, 180, 90);
    path.AddArc(rect.X + rect.Width - d, rect.Y, d, d, 270, 90);
    path.AddArc(rect.X + rect.Width - d, rect.Y + rect.Height - d, d, d, 0, 90);
    path.AddArc(rect.X, rect.Y + rect.Height - d, d, d, 90, 90);
    path.CloseFigure();
}

Popup::Popup(const wchar_t *className, bool clickThrough) : className_(className), clickThrough_(clickThrough) {}

Popup::~Popup() {
    if (window_) DestroyWindow(window_);
}

int Popup::Margin() { return Scaled(16); }

bool Popup::Ensure() {
    if (window_) return true;
    StartGdiplus();
    WNDCLASSEXW type = {sizeof(type)};
    type.lpfnWndProc = Procedure;
    type.hInstance = g_module;
    type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    type.lpszClassName = className_;
    RegisterClassExW(&type);  // fails harmlessly when already registered by another instance
    DWORD style = WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
    if (clickThrough_) style |= WS_EX_TRANSPARENT;  // the mouse goes to the app underneath
    window_ = CreateWindowExW(style, className_, L"", WS_POPUP, 0, 0, 0, 0, nullptr, nullptr, g_module, this);
    return window_ != nullptr;
}

void Popup::Present(POINT at, SIZE content) {
    if (!Ensure()) return;
    at_ = at;
    content_ = content;
    if (!shown_ || fadingOut_) {
        bool fresh = !shown_;
        shown_ = true;
        fadingOut_ = false;
        fadeFrom_ = fresh ? 0.f : alpha_;
        alpha_ = fadeFrom_;
        rise_ = fresh;
        fadeStart_ = GetTickCount64();
        if (Motion()) {
            offset_ = rise_ ? Scaled(8) : 0;
            Animating();
        } else {
            alpha_ = 1;
            offset_ = 0;
        }
    }
    Render();
    SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void Popup::Hide() {
    if (!window_ || !shown_ || fadingOut_) return;
    if (!Motion()) {
        shown_ = false;
        alpha_ = 0;
        KillTimer(window_, AnimationTimer);
        ShowWindow(window_, SW_HIDE);
        return;
    }
    fadingOut_ = true;
    fadeFrom_ = alpha_;
    fadeStart_ = GetTickCount64();
    Animating();
}

void Popup::Redraw() {
    if (window_ && shown_) Render();
}

void Popup::Animating() {
    if (window_) SetTimer(window_, AnimationTimer, 15, nullptr);
}

void Popup::Frame() {
    ULONGLONG now = GetTickCount64();
    bool moving = Animate(now);
    bool fading = false;
    if (fadingOut_) {
        float t = static_cast<float>(now - fadeStart_) / FadeOut;
        if (t >= 1) {
            fadingOut_ = false;
            shown_ = false;
            alpha_ = 0;
            KillTimer(window_, AnimationTimer);
            ShowWindow(window_, SW_HIDE);
            return;
        }
        alpha_ = fadeFrom_ * (1 - t);
        fading = true;
    } else if (shown_ && (alpha_ < 1 || offset_ != 0)) {
        float t = static_cast<float>(now - fadeStart_) / FadeIn;
        if (t >= 1) {
            alpha_ = 1;
            offset_ = 0;
        } else {
            float eased = EaseOut(t);
            alpha_ = fadeFrom_ + (1 - fadeFrom_) * eased;
            offset_ = rise_ ? static_cast<int>((1 - eased) * Scaled(8)) : 0;
            fading = true;
        }
    }
    if (moving) Render();
    else Place();
    if (!fading && !moving) KillTimer(window_, AnimationTimer);
}

void Popup::Place() {
    int margin = Margin();
    POINT to = {at_.x - margin, at_.y - margin + offset_};
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, static_cast<BYTE>(alpha_ * 255 + 0.5f), AC_SRC_ALPHA};
    UpdateLayeredWindow(window_, nullptr, &to, nullptr, nullptr, nullptr, 0, &blend, ULW_ALPHA);
}

void Popup::Render() {
    int margin = Margin();
    SIZE size = {content_.cx + 2 * margin, content_.cy + 2 * margin};
    BITMAPINFO info = {};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = size.cx;
    info.bmiHeader.biHeight = -size.cy;  // top-down
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void *bits = nullptr;
    HDC screen = GetDC(nullptr);
    HDC dc = CreateCompatibleDC(screen);
    HBITMAP bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!bitmap || !bits) {
        if (bitmap) DeleteObject(bitmap);
        DeleteDC(dc);
        ReleaseDC(nullptr, screen);
        return;
    }
    HGDIOBJ old = SelectObject(dc, bitmap);
    {
        Gdiplus::Bitmap canvas(size.cx, size.cy, size.cx * 4, PixelFormat32bppPARGB, static_cast<BYTE *>(bits));
        Gdiplus::Graphics graphics(&canvas);
        graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHalf);
        graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
        graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
        Palette colours = Colours();
        float radius = static_cast<float>(Scaled(10));
        // A soft shadow, a little below the box, fading out over the margin.
        float strength = colours.dark ? 16.f : 9.f;
        for (int k = margin; k >= 1; --k) {
            float spread = static_cast<float>(k), weight = 1.f - spread / (margin + 1);
            Gdiplus::GraphicsPath shade;
            RoundedRect(shade, Gdiplus::RectF(margin - spread, margin - spread + Scaled(3), content_.cx + 2 * spread,
                                              content_.cy + 2 * spread), radius + spread);
            Gdiplus::SolidBrush brush(Gdiplus::Color(static_cast<BYTE>(strength * weight * weight), 0, 0, 0));
            graphics.FillPath(&brush, &shade);
        }
        Gdiplus::GraphicsPath box;
        RoundedRect(box, Gdiplus::RectF(static_cast<float>(margin), static_cast<float>(margin),
                                        static_cast<float>(content_.cx), static_cast<float>(content_.cy)), radius);
        Gdiplus::SolidBrush surface(Colour(colours.surface));
        graphics.FillPath(&surface, &box);
        Gdiplus::Pen border(Colour(colours.border), 1.f);
        graphics.DrawPath(&border, &box);
        graphics.TranslateTransform(static_cast<float>(margin), static_cast<float>(margin));
        Draw(graphics, colours);
    }
    POINT source = {0, 0}, to = {at_.x - margin, at_.y - margin + offset_};
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, static_cast<BYTE>(alpha_ * 255 + 0.5f), AC_SRC_ALPHA};
    UpdateLayeredWindow(window_, screen, &to, &size, dc, &source, 0, &blend, ULW_ALPHA);
    SelectObject(dc, old);
    DeleteObject(bitmap);
    DeleteDC(dc);
    ReleaseDC(nullptr, screen);
}

LRESULT CALLBACK Popup::Procedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_NCCREATE) {
        auto *create = reinterpret_cast<CREATESTRUCTW *>(lParam);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto *self = reinterpret_cast<Popup *>(GetWindowLongPtrW(window, GWLP_USERDATA));
    // The content's own coordinates: the box without the shadow's margin.
    auto inside = [&] { return POINT{GET_X_LPARAM(lParam) - Margin(), GET_Y_LPARAM(lParam) - Margin()}; };
    switch (message) {
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;  // a click never takes the focus from the app being typed in
        case WM_NCHITTEST:
            if (self && self->clickThrough_) return HTTRANSPARENT;
            break;
        case WM_TIMER:
            if (!self) return 0;
            if (wParam == AnimationTimer) self->Frame();
            else self->OnTimer(wParam);
            return 0;
        case WM_LBUTTONDOWN:
            if (self) self->Click(inside());
            return 0;
        case WM_MOUSEMOVE:
            if (!self) return 0;
            if (!self->tracking_) {
                TRACKMOUSEEVENT track = {sizeof(track), TME_LEAVE, window, 0};
                self->tracking_ = TrackMouseEvent(&track) != FALSE;
            }
            self->Hover(inside());
            return 0;
        case WM_MOUSELEAVE:
            if (!self) return 0;
            self->tracking_ = false;
            self->Hover({-1, -1});
            return 0;
        case WM_SETCURSOR: {
            if (!self) break;
            POINT at = {};
            GetCursorPos(&at);
            ScreenToClient(window, &at);
            at.x -= Margin();
            at.y -= Margin();
            SetCursor(LoadCursorW(nullptr, self->HandAt(at) ? IDC_HAND : IDC_ARROW));
            return TRUE;
        }
        default:
            break;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

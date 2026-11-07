#include "PreviewWindow.h"

namespace {
const UINT_PTR PauseTimer = 1;
const int PadX = 14, PadY = 8, LineGap = 5;  // LineGap: room under the text for the dashed line
const ULONGLONG GlideTime = 180;             // ms, as on the Mac

Gdiplus::Font ArabicFont() { return Gdiplus::Font(ArabicFamily(), static_cast<float>(Scaled(22)), 0, Gdiplus::UnitPixel); }
Gdiplus::Font LatinFont() { return Gdiplus::Font(LatinFamily(), static_cast<float>(Scaled(16)), 0, Gdiplus::UnitPixel); }
Gdiplus::Font HintFont() { return Gdiplus::Font(LatinFamily(), static_cast<float>(Scaled(12)), 0, Gdiplus::UnitPixel); }

bool Same(const Gdiplus::RectF &a, const Gdiplus::RectF &b) {
    return a.X == b.X && a.Y == b.Y && a.Width == b.Width && a.Height == b.Height;
}
}  // namespace

PreviewWindow::PreviewWindow() : Popup(L"HarfiPreview", true) {}

RECT PreviewWindow::Show(const std::vector<std::wstring> &arabic, const std::vector<int> &doubtful, int selected,
                         const std::wstring &latin, const std::wstring &hint, const RECT &text) {
    if (!Ensure()) return text;
    Gdiplus::Font arabicFont = ArabicFont(), latinFont = LatinFont(), hintFont = HintFont();
    runs_.clear();
    for (size_t i = 0; i < arabic.size(); ++i) {
        bool dotted = false;
        for (int index : doubtful) dotted = dotted || index == static_cast<int>(i);
        runs_.push_back({arabic[i], Kind::Arabic, dotted});
    }
    if (!latin.empty()) runs_.push_back({latin, Kind::Latin});
    if (!hint.empty()) runs_.push_back({hint, Kind::Hint});

    // Right to left, as Arabic reads: the first word on the right, then the Latin typed since and the hint.
    // A space, but never narrower than the highlight needs to sit around a word without touching the next one.
    float space = Measure(L" ", arabicFont, true).Width, width = 0, height = 0;
    if (space < Scaled(16)) space = static_cast<float>(Scaled(16));
    std::vector<Gdiplus::SizeF> sizes;
    for (const Run &run : runs_) {
        const Gdiplus::Font &font = run.kind == Kind::Arabic ? arabicFont : run.kind == Kind::Latin ? latinFont : hintFont;
        Gdiplus::SizeF size = Measure(run.text, font, run.kind == Kind::Arabic);
        sizes.push_back(size);
        width += size.Width + (sizes.size() > 1 ? (run.kind == Kind::Hint ? 3 * space : space) : 0);
        if (size.Height > height) height = size.Height;
    }
    SIZE content = {static_cast<LONG>(width + 0.99f) + 2 * Scaled(PadX),
                    static_cast<LONG>(height + 0.99f) + 2 * Scaled(PadY) + Scaled(LineGap)};
    float right = static_cast<float>(content.cx - Scaled(PadX));
    for (size_t i = 0; i < runs_.size(); ++i) {
        if (i > 0) right -= runs_[i].kind == Kind::Hint ? 3 * space : space;
        float top = Scaled(PadY) + (height - sizes[i].Height) / 2;
        runs_[i].box = Gdiplus::RectF(right - sizes[i].Width, top, sizes[i].Width, sizes[i].Height);
        right -= sizes[i].Width;
    }

    // The highlight: fades in on the first word, then glides to the next one.
    ULONGLONG now = GetTickCount64();
    if (selected >= 0 && selected < static_cast<int>(runs_.size())) {
        Gdiplus::RectF to = runs_[selected].box;
        to.Inflate(static_cast<float>(Scaled(4)), static_cast<float>(Scaled(2)));
        if (!highlight_) {
            shown_ = from_ = to_ = to;
            opacity_ = Motion() ? 0.f : 1.f;
            gliding_ = Motion();
        } else if (!Same(to, to_)) {
            from_ = shown_;
            to_ = to;
            gliding_ = Motion();
            if (!gliding_) shown_ = to;
        }
        glideStart_ = now;
        highlight_ = true;
    } else {
        highlight_ = gliding_ = false;
        opacity_ = 0;
    }
    Present(PlaceAbove(text, content), content);
    if (gliding_) Animating();
    return Box();
}

bool PreviewWindow::Animate(ULONGLONG now) {
    if (!gliding_) return false;
    float t = static_cast<float>(now - glideStart_) / GlideTime;
    if (t > 1) t = 1;
    float eased = t * t * (3 - 2 * t);
    auto mix = [&](float a, float b) { return a + (b - a) * eased; };
    shown_ = Gdiplus::RectF(mix(from_.X, to_.X), mix(from_.Y, to_.Y), mix(from_.Width, to_.Width),
                            mix(from_.Height, to_.Height));
    if (eased > opacity_) opacity_ = eased;
    if (t >= 1) gliding_ = false;
    return true;  // this frame is drawn, the last one too
}

void PreviewWindow::Draw(Gdiplus::Graphics &graphics, const Palette &colours) {
    if (highlight_ && opacity_ > 0) {  // a clear cedar outline and fill, under the letters
        Gdiplus::GraphicsPath pill;
        RoundedRect(pill, shown_, static_cast<float>(Scaled(6)));
        Gdiplus::SolidBrush fill(Colour(colours.accent, static_cast<int>(46 * opacity_)));
        graphics.FillPath(&fill, &pill);
        Gdiplus::Pen outline(Colour(colours.accent, static_cast<int>(230 * opacity_)), 1.5f * Scaled(1));
        graphics.DrawPath(&outline, &pill);
    }
    Gdiplus::Font arabicFont = ArabicFont(), latinFont = LatinFont(), hintFont = HintFont();
    for (const Run &run : runs_) {
        switch (run.kind) {
            case Kind::Arabic: Write(graphics, run.text, arabicFont, colours.text, run.box, true); break;
            case Kind::Latin: Write(graphics, run.text, latinFont, colours.muted, run.box, false); break;
            case Kind::Hint: Write(graphics, run.text, hintFont, colours.accent, run.box, false); break;
        }
        if (run.doubtful) {  // a dashed line below the lowest letters: this word may be wrong
            Gdiplus::Pen dashes(Colour(colours.warning), 1.5f * Scaled(1));
            Gdiplus::REAL pattern[] = {2.7f, 2.f};
            dashes.SetDashPattern(pattern, 2);
            dashes.SetDashCap(Gdiplus::DashCapRound);
            float y = run.box.GetBottom() + Scaled(3);
            graphics.DrawLine(&dashes, run.box.X, y, run.box.GetRight(), y);
        }
    }
}

void PreviewWindow::AfterPause(UINT milliseconds, std::function<void()> paused) {
    if (!Ensure()) return;
    paused_ = std::move(paused);
    SetTimer(window_, PauseTimer, milliseconds, nullptr);
}

void PreviewWindow::CancelPause() {
    if (window_) KillTimer(window_, PauseTimer);
    paused_ = nullptr;
}

void PreviewWindow::OnTimer(UINT_PTR id) {
    if (id != PauseTimer) return;
    KillTimer(window_, PauseTimer);
    auto paused = std::move(paused_);
    paused_ = nullptr;
    if (paused) paused();
}

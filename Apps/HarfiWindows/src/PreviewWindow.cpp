#include "PreviewWindow.h"

namespace {
const UINT_PTR PauseTimer = 1;
const int PadX = 14, PadY = 8, LineGap = 5;  // LineGap: room under the text for the dashed line
const ULONGLONG GlideTime = 180;             // ms, as on the Mac

Gdiplus::Font ArabicFont() { return Gdiplus::Font(ArabicFamily(), static_cast<float>(Scaled(22)), 0, Gdiplus::UnitPixel); }
Gdiplus::Font LatinFont() {  // italic: the Latin typed since, not yet converted
    return Gdiplus::Font(LatinFamily(), static_cast<float>(Scaled(16)), Gdiplus::FontStyleItalic, Gdiplus::UnitPixel);
}
Gdiplus::Font HintFont() { return Gdiplus::Font(LatinFamily(), static_cast<float>(Scaled(12)), 0, Gdiplus::UnitPixel); }
// An English word in the converted line: upright, sized so its letters sit evenly with Noto Naskh's at 22.
Gdiplus::Font EnglishFont() { return Gdiplus::Font(LatinFamily(), static_cast<float>(Scaled(18)), 0, Gdiplus::UnitPixel); }

// A converted word written in Latin letters only (kept as typed): drawn as English, not with the Arabic font.
bool IsEnglish(const std::wstring &word) {
    bool latin = false;
    for (wchar_t c : word) {
        if (c >= 0x0600 && c <= 0x06FF) return false;
        latin = latin || (c >= L'A' && c <= L'Z') || (c >= L'a' && c <= L'z');
    }
    return latin;
}

bool Same(const Gdiplus::RectF &a, const Gdiplus::RectF &b) {
    return a.X == b.X && a.Y == b.Y && a.Width == b.Width && a.Height == b.Height;
}
}  // namespace

PreviewWindow::PreviewWindow() : Popup(L"HarfiPreview", true) {}

RECT PreviewWindow::Show(const std::vector<std::wstring> &arabic, const std::vector<int> &doubtful, int selected,
                         const std::wstring &latin, const std::wstring &hint, const RECT &text) {
    if (!Ensure()) return text;
    Gdiplus::Font arabicFont = ArabicFont(), latinFont = LatinFont(), hintFont = HintFont(), englishFont = EnglishFont();
    runs_.clear();
    bool anyDotted = false;
    for (size_t i = 0; i < arabic.size(); ++i) {
        bool dotted = false;
        for (int index : doubtful) dotted = dotted || index == static_cast<int>(i);
        anyDotted = anyDotted || dotted;
        runs_.push_back({arabic[i], IsEnglish(arabic[i]) ? Kind::English : Kind::Arabic, dotted});
    }
    if (!latin.empty()) runs_.push_back({latin, Kind::Latin});
    if (!hint.empty()) runs_.push_back({hint, Kind::Hint});

    // Right to left, as Arabic reads: the first word on the right, then the Latin typed since and the hint
    // (left to right instead when no word is Arabic, below).
    // A space, but never narrower than the highlight needs to sit around a word without touching the next one.
    // Every word sits on one baseline, and the box is centred on the letters as drawn (from the highest to the
    // lowest), not on each font's line, which for Noto Naskh has much more room above and below than Segoe UI.
    float space = Measure(L" ", arabicFont, true).Width, width = 0;
    if (space < Scaled(16)) space = static_cast<float>(Scaled(16));
    float high = 0, low = 0;  // the letters' extent above (negative) and below the baseline
    bool any = false;
    std::vector<float> widths;
    auto fontOf = [&](Kind kind) -> const Gdiplus::Font & {
        return kind == Kind::Arabic ? arabicFont : kind == Kind::English ? englishFont
             : kind == Kind::Latin ? latinFont : hintFont;
    };
    for (const Run &run : runs_) {
        const Gdiplus::Font &font = fontOf(run.kind);
        bool rtl = run.kind == Kind::Arabic;
        float w = Measure(run.text, font, rtl).Width;
        widths.push_back(w);
        width += w + (widths.size() > 1 ? (run.kind == Kind::Hint ? 3 * space : space) : 0);
        Gdiplus::RectF ink = Ink(run.text, font, rtl ? ArabicFamily() : LatinFamily(), rtl, w);
        if (ink.Height <= 0) continue;
        high = any ? (ink.Y < high ? ink.Y : high) : ink.Y;
        low = any ? (ink.GetBottom() > low ? ink.GetBottom() : low) : ink.GetBottom();
        any = true;
    }
    if (!any) {  // nothing drawn: the Arabic font's own line
        high = -Ascent(arabicFont, ArabicFamily());
        low = LineHeight(arabicFont, ArabicFamily()) + high;
    }
    float height = low - high;
    // Room under the letters only when a word has the dashed line; otherwise the words sit in the middle.
    SIZE content = {static_cast<LONG>(width + 0.99f) + 2 * Scaled(PadX),
                    static_cast<LONG>(height + 0.99f) + 2 * Scaled(PadY) + (anyDotted ? Scaled(LineGap) : 0)};
    baseline_ = Scaled(PadY) - high;
    // Left to right when no word is Arabic (an English sentence, sent as it is), as the app will show it.
    bool leftToRight = true;
    for (const Run &run : runs_) leftToRight = leftToRight && run.kind != Kind::Arabic;
    float right = static_cast<float>(content.cx - Scaled(PadX)), left = static_cast<float>(Scaled(PadX));
    for (size_t i = 0; i < runs_.size(); ++i) {
        float gap = i == 0 ? 0 : runs_[i].kind == Kind::Hint ? 3 * space : space;
        if (leftToRight) {
            left += gap;
            runs_[i].box = Gdiplus::RectF(left, baseline_ + high, widths[i], height);
            left += widths[i];
        } else {
            right -= gap;
            runs_[i].box = Gdiplus::RectF(right - widths[i], baseline_ + high, widths[i], height);
            right -= widths[i];
        }
    }

    // The highlight: fades in on the first word, then glides to the next one.
    ULONGLONG now = GetTickCount64();
    selected_ = selected >= 0 && selected < static_cast<int>(runs_.size()) ? selected : -1;
    if (selected >= 0 && selected < static_cast<int>(runs_.size())) {
        Gdiplus::RectF to = runs_[selected].box;
        to.Inflate(static_cast<float>(Scaled(5)), static_cast<float>(Scaled(4)));
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
    if (highlight_ && opacity_ > 0) {  // solid cedar under the word being fixed, fading in, then gliding
        Gdiplus::GraphicsPath pill;
        RoundedRect(pill, shown_, static_cast<float>(Scaled(6)));
        Gdiplus::SolidBrush fill(Colour(colours.accent, static_cast<int>(255 * opacity_)));
        graphics.FillPath(&fill, &pill);
    }
    Gdiplus::Font arabicFont = ArabicFont(), latinFont = LatinFont(), hintFont = HintFont(), englishFont = EnglishFont();
    for (size_t i = 0; i < runs_.size(); ++i) {
        const Run &run = runs_[i];
        float x = run.box.X, w = run.box.Width;
        // White on the highlight once it has (nearly) arrived under the word.
        bool onCedar = highlight_ && static_cast<int>(i) == selected_ && opacity_ > 0.5f && !gliding_;
        switch (run.kind) {
            case Kind::Arabic:
                WriteOnBaseline(graphics, run.text, arabicFont, ArabicFamily(), onCedar ? colours.onAccent : colours.text,
                                x, w, baseline_, true);
                break;
            case Kind::English:
                WriteOnBaseline(graphics, run.text, englishFont, LatinFamily(), onCedar ? colours.onAccent : colours.text,
                                x, w, baseline_, false);
                break;
            case Kind::Latin:
                WriteOnBaseline(graphics, run.text, latinFont, LatinFamily(), colours.latin, x, w, baseline_, false);
                break;
            case Kind::Hint:
                WriteOnBaseline(graphics, run.text, hintFont, LatinFamily(), colours.accent, x, w, baseline_, false);
                break;
        }
        if (run.doubtful && !onCedar) {  // a dashed amber line below the lowest letters: this word may be wrong
            Gdiplus::Pen dashes(Colour(colours.warningLine), 1.5f * Scaled(1));
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

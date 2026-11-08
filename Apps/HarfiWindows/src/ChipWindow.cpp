#include "ChipWindow.h"

namespace {
const UINT_PTR HintTimer = 1;
const wchar_t SpellValue[] = L"\x01spell";
const int Gap = 6, PadX = 10, PadY = 4, Inset = 6, MinHeight = 32, NumberGap = 6;

Gdiplus::Font ArabicFont() { return Gdiplus::Font(ArabicFamily(), static_cast<float>(Scaled(20)), 0, Gdiplus::UnitPixel); }
Gdiplus::Font NumberFont() { return Gdiplus::Font(LatinFamily(), static_cast<float>(Scaled(12)), 0, Gdiplus::UnitPixel); }
Gdiplus::Font QuietFont() { return Gdiplus::Font(LatinFamily(), static_cast<float>(Scaled(13)), 0, Gdiplus::UnitPixel); }
const wchar_t Pencil[] = L"\uE70F";  // "Edit" in Windows' icon font, before "Spell it"
}  // namespace

ChipWindow::ChipWindow() : Popup(L"HarfiChips", false) {}

void ChipWindow::Show(const Effect &effect, const RECT &text, Pick pick, SpellIt spellIt) {
    pick_ = std::move(pick);
    spellIt_ = std::move(spellIt);
    if (!Ensure()) return;
    KillTimer(window_, HintTimer);
    chips_.clear();
    if (!effect.word.empty() && !effect.spelling) {  // the word being fixed, first (on the right)
        Chip current;
        current.style = Style::Current;
        current.label = effect.word;
        current.doubtful = effect.wordDoubtful;
        chips_.push_back(current);
    }
    for (size_t i = 0; i < effect.candidates.size(); ++i) {
        Chip spelling;
        spelling.style = Style::Spelling;
        spelling.label = spelling.value = effect.candidates[i];
        if (!effect.spelling && i < 9) spelling.number = std::to_wstring(i + 1);
        spelling.selected = static_cast<int>(i) == effect.choice;
        chips_.push_back(spelling);
    }
    Chip last;
    if (effect.spelling) {
        last.label = effect.candidates.empty() ? L"Type the word" : L"Tab changes it · Enter takes it";
    } else {
        last.style = Style::Quiet;
        last.label = L"Spell it";
        last.value = SpellValue;
    }
    chips_.push_back(last);
    Arrange(text);
}

void ChipWindow::ShowHint(const std::wstring &hint, const RECT &text, UINT milliseconds) {
    if (!Ensure()) return;
    chips_.clear();
    Chip tip;
    tip.label = hint;
    chips_.push_back(tip);
    Arrange(text);
    SetTimer(window_, HintTimer, milliseconds, nullptr);
}

void ChipWindow::Hide() {
    if (window_) KillTimer(window_, HintTimer);
    hovered_ = -1;
    Popup::Hide();
}

void ChipWindow::OnTimer(UINT_PTR id) {
    if (id == HintTimer) Hide();
}

// Lays the chips out right to left (the first on the right) and shows the row above the text.
void ChipWindow::Arrange(const RECT &text) {
    Gdiplus::Font arabic = ArabicFont(), number = NumberFont(), quiet = QuietFont();
    // One baseline for the whole row, centred on the letters as drawn (highest to lowest), so the Latin number or
    // arrow and the Arabic word line up and sit in the middle of their chip.
    float high = 0, low = 0;
    bool any = false;
    auto reach = [&](const std::wstring &text, const Gdiplus::Font &font, bool rtl, float width) {
        Gdiplus::RectF ink = Ink(text, font, rtl ? ArabicFamily() : LatinFamily(), rtl, width);
        if (ink.Height <= 0) return;
        high = any ? (ink.Y < high ? ink.Y : high) : ink.Y;
        low = any ? (ink.GetBottom() > low ? ink.GetBottom() : low) : ink.GetBottom();
        any = true;
    };
    std::vector<float> widths;
    for (Chip &chip : chips_) {
        bool isArabic = chip.style == Style::Spelling || chip.style == Style::Current;
        const Gdiplus::Font &labelFont = isArabic ? arabic : quiet;
        Gdiplus::SizeF label = Measure(chip.label, labelFont, isArabic);
        reach(chip.label, labelFont, isArabic, label.Width);
        Gdiplus::SizeF extra = {};
        if (!chip.number.empty()) {
            extra = Measure(chip.number, number, false);
            reach(chip.number, number, false, extra.Width);
        }
        if (chip.style == Style::Current) {
            extra = Measure(L"←", quiet, false);
            reach(L"←", quiet, false, extra.Width);
        }
        if (chip.style == Style::Quiet && IconFamily()) {  // the pencil: not in the baseline's reach, it is centred
            Gdiplus::Font icon(IconFamily(), static_cast<float>(Scaled(13)), 0, Gdiplus::UnitPixel);
            extra = Measure(Pencil, icon, false);
        }
        float inner = label.Width + (extra.Width > 0 ? extra.Width + Scaled(NumberGap) : 0);
        widths.push_back(inner + 2 * Scaled(PadX));
        // Inside a chip: the number (or the arrow) on the left, the label on the right.
        chip.numberBox = Gdiplus::RectF(0, 0, extra.Width, 0);
        chip.labelBox = Gdiplus::RectF(0, 0, label.Width, 0);
    }
    if (!any) {
        high = -Ascent(arabic, ArabicFamily());
        low = LineHeight(arabic, ArabicFamily()) + high;
    }
    float letters = low - high, height = letters + 2 * Scaled(PadY);
    if (height < Scaled(MinHeight)) height = static_cast<float>(Scaled(MinHeight));
    float total = 0;
    for (size_t i = 0; i < widths.size(); ++i) total += widths[i] + (i ? Scaled(Gap) : 0);
    SIZE content = {static_cast<LONG>(total + 0.99f) + 2 * Scaled(Inset), static_cast<LONG>(height + 0.99f) + 2 * Scaled(Inset)};
    float right = static_cast<float>(content.cx - Scaled(Inset)), top = static_cast<float>(Scaled(Inset));
    baseline_ = top + (height - letters) / 2 - high;
    for (size_t i = 0; i < chips_.size(); ++i) {
        Chip &chip = chips_[i];
        chip.box = Gdiplus::RectF(right - widths[i], top, widths[i], height);
        float labelRight = chip.box.GetRight() - Scaled(PadX);
        float lettersTop = baseline_ + high;
        chip.labelBox = Gdiplus::RectF(labelRight - chip.labelBox.Width, lettersTop, chip.labelBox.Width, letters);
        chip.numberBox = Gdiplus::RectF(chip.box.X + Scaled(PadX), lettersTop, chip.numberBox.Width, letters);
        right -= widths[i] + Scaled(Gap);
    }
    hovered_ = -1;
    Present(PlaceAbove(text, content), content);
}

void ChipWindow::Draw(Gdiplus::Graphics &graphics, const Palette &colours) {
    Gdiplus::Font arabic = ArabicFont(), number = NumberFont(), quiet = QuietFont();
    float radius = static_cast<float>(Scaled(8));
    // One chip is lit at a time: the one under the mouse while it is over a chip, else the chosen one (the arrows').
    int lit = hovered_;
    for (size_t i = 0; lit < 0 && i < chips_.size(); ++i) {
        if (chips_[i].selected) lit = static_cast<int>(i);
    }
    auto pill = [&](const Chip &chip, COLORREF fill, COLORREF line, bool dashed) {
        Gdiplus::RectF box = chip.box;
        box.Inflate(-0.5f, -0.5f);
        Gdiplus::GraphicsPath path;
        RoundedRect(path, box, radius);
        Gdiplus::SolidBrush brush(Colour(fill));
        graphics.FillPath(&brush, &path);
        if (line == fill) return;
        Gdiplus::Pen pen(Colour(line), dashed ? 1.25f * Scaled(1) : 1.f);
        if (dashed) {
            Gdiplus::REAL pattern[] = {3.f, 2.f};
            pen.SetDashPattern(pattern, 2);
        }
        graphics.DrawPath(&pen, &path);
    };
    for (size_t i = 0; i < chips_.size(); ++i) {
        const Chip &chip = chips_[i];
        bool on = static_cast<int>(i) == lit;
        switch (chip.style) {
            case Style::Spelling:  // white on the tint; the lit one solid cedar
                pill(chip, on ? colours.accent : colours.chip, on ? colours.accent : colours.border, false);
                if (!chip.number.empty()) {
                    WriteOnBaseline(graphics, chip.number, number, LatinFamily(),
                                    on ? colours.onAccentQuiet : colours.muted, chip.numberBox.X,
                                    chip.numberBox.Width, baseline_, false);
                }
                WriteOnBaseline(graphics, chip.label, arabic, ArabicFamily(), on ? colours.onAccent : colours.text,
                                chip.labelBox.X, chip.labelBox.Width, baseline_, true);
                break;
            case Style::Current: {  // the word being fixed: white, a dashed outline, amber when it looks wrong
                COLORREF ink = chip.doubtful ? colours.warning : colours.muted;
                pill(chip, colours.chip, chip.doubtful ? colours.warningLine : colours.accentLine, true);
                WriteOnBaseline(graphics, chip.label, arabic, ArabicFamily(), ink, chip.labelBox.X,
                                chip.labelBox.Width, baseline_, true);
                WriteOnBaseline(graphics, L"←", quiet, LatinFamily(), ink, chip.numberBox.X, chip.numberBox.Width,
                                baseline_, false);
                break;
            }
            case Style::Quiet:  // "Spell it": a soft cedar chip with a pencil; solid cedar under the mouse
                pill(chip, on ? colours.accent : colours.accentSoft, on ? colours.accent : colours.accentLine, false);
                if (IconFamily() && chip.numberBox.Width > 0) {
                    Gdiplus::Font icon(IconFamily(), static_cast<float>(Scaled(13)), 0, Gdiplus::UnitPixel);
                    Write(graphics, Pencil, icon, on ? colours.onAccent : colours.accent, chip.numberBox, false);
                }
                WriteOnBaseline(graphics, chip.label, quiet, LatinFamily(), on ? colours.onAccent : colours.accent,
                                chip.labelBox.X, chip.labelBox.Width, baseline_, false);
                break;
            case Style::Hint:
                WriteOnBaseline(graphics, chip.label, quiet, LatinFamily(), colours.muted, chip.labelBox.X,
                                chip.labelBox.Width, baseline_, false);
                break;
        }
    }
}

int ChipWindow::ChipAt(POINT at) const {
    for (size_t i = 0; i < chips_.size(); ++i) {
        const Chip &chip = chips_[i];
        if (!chip.value.empty() && chip.box.Contains(static_cast<float>(at.x), static_cast<float>(at.y))) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

void ChipWindow::Click(POINT at) {
    int index = ChipAt(at);
    if (index < 0) return;
    std::wstring value = chips_[index].value;  // the pick may replace the chips
    if (value == SpellValue) {
        if (spellIt_) spellIt_();
    } else if (pick_) {
        pick_(value);
    }
}

void ChipWindow::Hover(POINT at) {
    int index = at.x < 0 ? -1 : ChipAt(at);
    if (index == hovered_) return;
    hovered_ = index;
    Redraw();
}

bool ChipWindow::HandAt(POINT at) { return ChipAt(at) >= 0; }

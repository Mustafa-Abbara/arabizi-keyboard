// The row of spellings above the text while a word is fixed (↑, also right after converting, or Alt+Tab), as on the Mac (CorrectionChips): the
// word being fixed first (amber when it looks wrong), then the spellings with their number keys, then "Spell it";
// while spelling, the letters for the last key. Right to left, as Arabic reads. Above the chips, the sentence as
// typed, the typed word behind the selected word highlighted. It never takes the focus; a click picks a chip. It
// also shows the one-line tips.
#pragma once
#include <functional>
#include <vector>
#include "Core.h"
#include "Popup.h"

class ChipWindow : public Popup {
public:
    using Pick = std::function<void(const std::wstring &candidate)>;
    using SpellIt = std::function<void()>;
    using Point = std::function<void(const std::wstring &candidate)>;  // the mouse moved onto a spelling

    ChipWindow();
    // Shows the chips for `effect` just above `text` (screen coordinates).
    // When only the highlight changed (the same chips), the row stays where it is, so the chip under the mouse stays.
    void Show(const Effect &effect, const RECT &text, Pick pick, SpellIt spellIt, Point point = nullptr);
    // A one-line tip in the same place, gone after `milliseconds` (or when chips replace it).
    void ShowHint(const std::wstring &hint, const RECT &text, UINT milliseconds = 3000);
    void Hide();
    // Calls `due` once after `milliseconds` while the chips show (each call starts the wait again; Hide cancels it).
    void After(UINT milliseconds, std::function<void()> due);

protected:
    void Draw(Gdiplus::Graphics &graphics, const Palette &colours) override;
    void Click(POINT at) override;
    void Hover(POINT at) override;
    bool HandAt(POINT at) override;
    void OnTimer(UINT_PTR id) override;

private:
    enum class Style { Spelling, Quiet, Hint, Current };
    struct Chip {
        Style style = Style::Hint;
        std::wstring label;   // what is drawn (Arabic for spellings and the word being fixed)
        std::wstring number;  // the number key, for spellings
        std::wstring value;   // what a click picks; empty: not clickable
        bool selected = false, doubtful = false;
        Gdiplus::RectF box;
        Gdiplus::RectF numberBox, labelBox;
    };

    void Arrange(const RECT &text);
    int ChipAt(POINT at) const;

    std::vector<Chip> chips_;
    float baseline_ = 0;  // shared by every chip's text, so numbers, arrows and Arabic sit on one line
    // The sentence as typed, above the chips, with the selected word's typed part highlighted (UTF-16 range;
    // typedStart_ -1: nothing highlighted). Empty for tips.
    std::wstring typed_;
    int typedStart_ = -1, typedLength_ = 0;
    Gdiplus::RectF typedBox_;   // the line's room, right-aligned above the chips
    float typedBaseline_ = 0;
    int hovered_ = -1;
    Pick pick_;
    SpellIt spellIt_;
    Point point_;
    bool keepPlace_ = false;
    std::function<void()> due_;
};

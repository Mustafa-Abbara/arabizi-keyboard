// The row of spellings above the text while a word is fixed (↑ or Alt+Tab), as on the Mac (CorrectionChips):
// the word being fixed first, then the spellings with their number keys, then "Spell it". It never takes the
// focus; a click picks a chip. Colours from design/palette.json, light or dark as Windows is set.
#pragma once
#include <functional>
#include <string>
#include <vector>
#include "Core.h"
#include "Globals.h"

class ChipWindow {
public:
    using Pick = std::function<void(const std::wstring &candidate)>;
    using SpellIt = std::function<void()>;

    ~ChipWindow();
    // Shows the chips for `effect` just above `text` (the composition, in screen coordinates).
    void Show(const Effect &effect, const RECT &text, Pick pick, SpellIt spellIt);
    void Hide();

private:
    struct Chip {
        std::wstring label;  // what is drawn
        std::wstring value;  // what a click picks (empty: not clickable)
        bool number = false, selected = false, quiet = false;
        RECT box = {};
    };

    static LRESULT CALLBACK Procedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam);
    void Layout(HDC dc);
    void Paint(HDC dc);
    void Click(POINT at);

    HWND window_ = nullptr;
    HFONT arabic_ = nullptr, latin_ = nullptr;
    std::vector<Chip> chips_;
    SIZE size_ = {};
    Pick pick_;
    SpellIt spellIt_;
};

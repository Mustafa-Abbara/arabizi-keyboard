// The live preview box just above the text being typed, as on the Mac (PreviewWindow): the Arabic of the words
// converted so far, then the Latin typed since in a quieter colour. Doubtful words get a dashed line under them;
// while a word is fixed before sending it is highlighted (the highlight fades in, then glides from word to word),
// with the chip row above the box. The mouse goes through it. A timer tells the text service when typing pauses,
// so the word being typed shows too.
#pragma once
#include <functional>
#include <vector>
#include "Popup.h"

class PreviewWindow : public Popup {
public:
    PreviewWindow();
    // Shows the box just above `text` (the line being typed, screen coordinates); returns the box on screen.
    RECT Show(const std::vector<std::wstring> &arabic, const std::vector<int> &doubtful, int selected,
              const std::wstring &latin, const std::wstring &hint, const RECT &text);
    // Calls `paused` once, `milliseconds` after the last call (each call starts the wait again).
    void AfterPause(UINT milliseconds, std::function<void()> paused);
    void CancelPause();

protected:
    void Draw(Gdiplus::Graphics &graphics, const Palette &colours) override;
    bool Animate(ULONGLONG now) override;
    void OnTimer(UINT_PTR id) override;

private:
    enum class Kind { Arabic, Latin, Hint };
    struct Run {
        std::wstring text;
        Kind kind = Kind::Arabic;
        bool doubtful = false;
        Gdiplus::RectF box;  // the word's room in the line, from the line's highest letter to its lowest
    };
    float baseline_ = 0;  // shared by every word, so Arabic and Latin sit on one line
    int selected_ = -1;   // the highlighted word, drawn in white on the cedar highlight

    std::vector<Run> runs_;
    std::function<void()> paused_;
    // The highlight behind the word being fixed: where it is drawn now, and the glide in progress.
    bool highlight_ = false, gliding_ = false;
    Gdiplus::RectF shown_, from_, to_;
    ULONGLONG glideStart_ = 0;
    float opacity_ = 0;
};

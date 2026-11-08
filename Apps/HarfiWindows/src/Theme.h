// Cedar and sand (design/palette.json), always light whatever Windows is set to, with the cedar tint the user chose
// (option 2, 8 Nov 2026): the boxes are pale cedar, the chips white on them, the chosen chip and the highlighted word
// solid cedar. Sizes are scaled for the screen. Shared by the preview box and the chip row.
#pragma once
#include "Globals.h"

struct Palette {
    COLORREF surface = RGB(0xF1, 0xF6, 0xF3);      // the boxes: a pale cedar tint
    COLORREF border = RGB(0xD3, 0xE3, 0xDB);
    COLORREF chip = RGB(0xFF, 0xFF, 0xFF);         // a spelling, on the tint
    COLORREF text = RGB(0x1E, 0x2A, 0x25);
    COLORREF muted = RGB(0x6B, 0x75, 0x6F);
    COLORREF accent = RGB(0x2F, 0x6B, 0x5A);       // cedar: the chosen chip, the highlighted word
    COLORREF onAccent = RGB(0xFF, 0xFF, 0xFF);     // letters on cedar
    COLORREF onAccentQuiet = RGB(0xCF, 0xE3, 0xDA);  // a number on cedar
    COLORREF accentSoft = RGB(0xDC, 0xEB, 0xE4);   // "Spell it"
    COLORREF accentLine = RGB(0xB7, 0xD3, 0xC6);
    COLORREF latin = RGB(0x6B, 0x9C, 0x8A);        // the Latin typed since, in the preview
    COLORREF warning = RGB(0x9A, 0x6A, 0x1F);      // amber: a word that may be wrong
    COLORREF warningLine = RGB(0xC9, 0xA1, 0x5E);  // its dashed line and outline
    bool dark = false;
};

inline Palette Colours() { return Palette{}; }

// Windows' "Animation effects" setting (the Mac's Reduce Motion, the other way round).
inline bool Motion() {
    BOOL on = TRUE;
    SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &on, 0);
    return on != FALSE;
}

inline int Scaled(int value) { return MulDiv(value, static_cast<int>(GetDpiForSystem()), 96); }

// Where a box goes: just above `text` (the line being typed, in screen coordinates), below it when there is no room
// at the top, and always on the screen.
inline POINT PlaceAbove(const RECT &text, SIZE size) {
    HMONITOR monitor = MonitorFromRect(&text, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {sizeof(info)};
    GetMonitorInfoW(monitor, &info);
    POINT at = {text.left, text.top - size.cy - Scaled(6)};
    if (at.y < info.rcWork.top) at.y = text.bottom + Scaled(6);
    if (at.x + size.cx > info.rcWork.right) at.x = info.rcWork.right - size.cx - Scaled(4);
    if (at.x < info.rcWork.left) at.x = info.rcWork.left + Scaled(4);
    return at;
}

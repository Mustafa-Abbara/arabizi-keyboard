// Cedar and sand (design/palette.json), always the light colours whatever Windows is set to (the user's choice,
// 8 Nov 2026), and sizes scaled for the screen: shared by the preview box and the chip row.
#pragma once
#include "Globals.h"

struct Palette {
    COLORREF surface, text, muted, border, accent, accentSoft, warning;
    bool dark = false;
};

inline Palette Colours() {
    return {RGB(0xFF, 0xFF, 0xFF), RGB(0x1E, 0x2A, 0x25), RGB(0x6B, 0x75, 0x6F), RGB(0xE4, 0xDF, 0xD4),
            RGB(0x2F, 0x6B, 0x5A), RGB(0xE2, 0xEE, 0xE8), RGB(0x9A, 0x6A, 0x1F)};
}

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

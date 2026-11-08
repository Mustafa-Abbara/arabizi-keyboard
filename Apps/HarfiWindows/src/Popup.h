// A floating box above the text, drawn like the Mac's panels: GDI+ into a layered window with per-pixel alpha, so the
// rounded corners are smooth and a soft shadow falls under the box. It fades in while rising a few pixels into
// place, and fades out (no motion when Windows' animation effects are off). It never takes the focus. The preview
// box and the chip row draw their content on it.
#pragma once
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <string>
#include "Theme.h"

// The fonts Harfi draws with: Noto Naskh Arabic from the keyboard's folder (for this process only) and Segoe UI.
Gdiplus::FontFamily *ArabicFamily();
Gdiplus::FontFamily *LatinFamily();
// The space `text` takes in `font`, right to left for Arabic.
Gdiplus::SizeF Measure(const std::wstring &text, const Gdiplus::Font &font, bool rtl);
// Draws `text` centred in `box`.
void Write(Gdiplus::Graphics &graphics, const std::wstring &text, const Gdiplus::Font &font, COLORREF colour,
           const Gdiplus::RectF &box, bool rtl);
// Text on a shared baseline, so Arabic (Noto Naskh) and Latin (Segoe UI) words line up: how far the font's line
// rises above its baseline, the line's height, the letters' own outline (relative to the baseline, for `width` of
// layout), and `text` drawn in [x, x + width] with its baseline at `baseline`.
float Ascent(const Gdiplus::Font &font);
float LineHeight(const Gdiplus::Font &font);
Gdiplus::RectF Ink(const std::wstring &text, const Gdiplus::Font &font, bool rtl, float width);
void WriteOnBaseline(Gdiplus::Graphics &graphics, const std::wstring &text, const Gdiplus::Font &font,
                     COLORREF colour, float x, float width, float baseline, bool rtl);
void RoundedRect(Gdiplus::GraphicsPath &path, const Gdiplus::RectF &rect, float radius);
inline Gdiplus::Color Colour(COLORREF colour, int alpha = 255) {
    return Gdiplus::Color(static_cast<BYTE>(alpha), GetRValue(colour), GetGValue(colour), GetBValue(colour));
}

class Popup {
public:
    virtual ~Popup();
    // Fades the box out.
    void Hide();

protected:
    Popup(const wchar_t *className, bool clickThrough);
    bool Ensure();
    // Shows a box of `content` size with its top-left corner at `at` (screen), fading in when it was hidden.
    void Present(POINT at, SIZE content);
    // The content changed: draws it again in place.
    void Redraw();
    // Keeps frames coming while Animate() returns true.
    void Animating();
    // The box on screen, without its shadow.
    RECT Box() const { return {at_.x, at_.y, at_.x + content_.cx, at_.y + content_.cy}; }

    // The content, in a box of `content` size at (0, 0) whose surface and border are already drawn.
    virtual void Draw(Gdiplus::Graphics &graphics, const Palette &colours) = 0;
    // One frame of the content's own motion; true while it still moves.
    virtual bool Animate(ULONGLONG) { return false; }
    virtual void Click(POINT) {}
    virtual void Hover(POINT) {}  // (-1, -1) when the mouse left
    virtual bool HandAt(POINT) { return false; }
    virtual void OnTimer(UINT_PTR) {}

    HWND window_ = nullptr;

private:
    static LRESULT CALLBACK Procedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam);
    static int Margin();  // room around the box for the shadow
    void Render();        // draws everything and puts it on screen
    void Place();         // only the position and the fade changed
    void Frame();

    const wchar_t *className_;
    bool clickThrough_;
    POINT at_ = {};
    SIZE content_ = {};
    bool shown_ = false, fadingOut_ = false, rise_ = false, tracking_ = false;
    ULONGLONG fadeStart_ = 0;
    float alpha_ = 0, fadeFrom_ = 0;
    int offset_ = 0;  // how far below its place the box still is while it rises
};

// What the Harfi window (Settings.cpp) and the installer (Setup.cpp) both draw with, on top of the keyboard's own
// helpers (Popup.h, Theme.h): rounded boxes, wrapped text, UTF-8, and a picture of a drawing for checking it.
#pragma once
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <string>
#include <vector>
#include "../Popup.h"

inline std::wstring Wide(const std::string &text) {
    if (text.empty()) return L"";
    int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
    std::wstring out(static_cast<size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
    return out;
}

inline std::string Narrow(const std::wstring &text) {
    if (text.empty()) return "";
    int size = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
    std::string out(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size, nullptr, nullptr);
    return out;
}

// A rounded box, with a hairline border unless `border` is CLR_INVALID.
inline void FillBox(Gdiplus::Graphics &graphics, const Gdiplus::RectF &rect, float radius, COLORREF colour,
                    COLORREF border = CLR_INVALID) {
    Gdiplus::GraphicsPath path;
    RoundedRect(path, rect, radius);
    Gdiplus::SolidBrush brush(Colour(colour));
    graphics.FillPath(&brush, &path);
    if (border != CLR_INVALID) {
        Gdiplus::Pen pen(Colour(border), 1);
        graphics.DrawPath(&pen, &path);
    }
}

// Wrapped text from (x, y) in `width`; returns its height. With `draw` false it only measures.
inline float WrappedText(Gdiplus::Graphics &graphics, const std::wstring &text, const Gdiplus::Font &font,
                         COLORREF colour, float x, float y, float width, bool draw = true) {
    Gdiplus::StringFormat format;
    Gdiplus::RectF box(x, y, width, 10000), bounds;
    graphics.MeasureString(text.c_str(), static_cast<INT>(text.size()), &font, box, &format, &bounds);
    if (draw) {
        Gdiplus::SolidBrush brush(Colour(colour));
        graphics.DrawString(text.c_str(), static_cast<INT>(text.size()), &font, box, &format, &brush);
    }
    return bounds.Height;
}

inline bool SavePng(Gdiplus::Bitmap &bitmap, const std::wstring &file) {
    UINT count = 0, bytes = 0;
    Gdiplus::GetImageEncodersSize(&count, &bytes);
    std::vector<BYTE> buffer(bytes);
    auto *encoders = reinterpret_cast<Gdiplus::ImageCodecInfo *>(buffer.data());
    Gdiplus::GetImageEncoders(count, bytes, encoders);
    for (UINT i = 0; i < count; ++i) {
        if (std::wstring(encoders[i].MimeType) == L"image/png") {
            return bitmap.Save(file.c_str(), &encoders[i].Clsid, nullptr) == Gdiplus::Ok;
        }
    }
    return false;
}

// Draws a window's client area off screen first, then puts it on `dc` in one go (no flicker).
template <typename Draw> void PaintBuffered(HWND hwnd, Draw draw) {
    PAINTSTRUCT paint;
    HDC dc = BeginPaint(hwnd, &paint);
    RECT client;
    GetClientRect(hwnd, &client);
    SIZE size = {client.right, client.bottom};
    if (size.cx > 0 && size.cy > 0) {
        Gdiplus::Bitmap buffer(size.cx, size.cy, PixelFormat32bppPARGB);
        Gdiplus::Graphics graphics(&buffer);
        draw(graphics, size);
        Gdiplus::Graphics screen(dc);
        screen.DrawImage(&buffer, 0, 0);
    }
    EndPaint(hwnd, &paint);
}

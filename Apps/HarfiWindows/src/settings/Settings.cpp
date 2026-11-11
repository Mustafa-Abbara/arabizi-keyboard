// harfi-settings.exe: the Harfi window on Windows (the Mac's SettingsWindow.swift): Welcome, Typing, Your words,
// Privacy and Help. Drawn with GDI+ in the keyboard's colours (Theme.h), one window with no child controls: the
// mouse, Tab, Space/Enter and the arrow keys work on the parts drawn. It reads and changes the settings file and the
// user's own words through HarfiCoreC.dll (SettingsAPI.swift), next to it in the keyboard's folder; it never sees
// what is typed.
//
//   harfi-settings.exe [--welcome | --tab welcome|typing|words|privacy|help]
//   harfi-settings.exe --set livePreview|fasterPreview 0|1    changes one setting and exits (0 when written)
//   harfi-settings.exe --render FILE.png [--tab NAME] [--demo]   draws the window into a picture and exits (for
//                                                                checking the drawing; --demo: made-up words)
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <objidl.h>
#include <gdiplus.h>
#include <algorithm>
#include <atomic>
#include <functional>
#include <sstream>
#include <string>
#include <vector>
#include "Ui.h"

HINSTANCE g_module = nullptr;
std::atomic<long> g_objects{0};

std::wstring ModuleFolder() {
    wchar_t path[MAX_PATH] = {};
    DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring folder(path, length);
    size_t slash = folder.find_last_of(L'\\');
    return slash == std::wstring::npos ? L"." : folder.substr(0, slash);
}

void DebugLog(const char *) {}

namespace {
const wchar_t *ClassName = L"HarfiSettingsWindow";
const int Width = 560, Height = 560;  // at 96 DPI

// The settings and the user's words, through HarfiCoreC.dll. Without the library (a bare build folder) the window
// still opens: the switches show their defaults and change nothing.
struct Core {
    HMODULE library = nullptr;
    int (*settingGet)(const char *) = nullptr;
    int (*settingSet)(const char *, int) = nullptr;
    char *(*wordsList)() = nullptr;
    int (*wordsForget)(const char *, const char *) = nullptr;
    int (*wordsRefuse)(const char *, const char *) = nullptr;
    int (*wordsAllow)(const char *, const char *) = nullptr;
    int (*wordsWipe)() = nullptr;
    void (*release)(char *) = nullptr;

    void Load() {
        SetDllDirectoryW(ModuleFolder().c_str());  // the Swift runtime DLLs are next to it
        library = LoadLibraryW((ModuleFolder() + L"\\HarfiCoreC.dll").c_str());
        if (!library) return;
        auto find = [&](const char *name) { return reinterpret_cast<void *>(GetProcAddress(library, name)); };
        settingGet = reinterpret_cast<int (*)(const char *)>(find("harfi_setting_get"));
        settingSet = reinterpret_cast<int (*)(const char *, int)>(find("harfi_setting_set"));
        wordsList = reinterpret_cast<char *(*)()>(find("harfi_words_list"));
        wordsForget = reinterpret_cast<int (*)(const char *, const char *)>(find("harfi_words_forget"));
        wordsRefuse = reinterpret_cast<int (*)(const char *, const char *)>(find("harfi_words_refuse"));
        wordsAllow = reinterpret_cast<int (*)(const char *, const char *)>(find("harfi_words_allow"));
        wordsWipe = reinterpret_cast<int (*)()>(find("harfi_words_wipe"));
        release = reinterpret_cast<void (*)(char *)>(find("harfi_free"));
    }
};

struct Pair {
    std::wstring latin, arabic;
    int times = 0;
};

struct Words {
    int fixes = 0;
    std::vector<Pair> habits, refused, words;
};

Words ParseWords(const std::string &lines) {
    Words out;
    std::istringstream stream(lines);
    std::string line;
    while (std::getline(stream, line)) {
        std::vector<std::string> fields;
        size_t from = 0;
        for (size_t tab; (tab = line.find('\t', from)) != std::string::npos; from = tab + 1) {
            fields.push_back(line.substr(from, tab - from));
        }
        fields.push_back(line.substr(from));
        if (fields[0] == "fixes" && fields.size() >= 2) out.fixes = std::atoi(fields[1].c_str());
        if (fields.size() < 3) continue;
        Pair pair{Wide(fields[1]), Wide(fields[2]), fields.size() >= 4 ? std::atoi(fields[3].c_str()) : 0};
        if (fields[0] == "habit") out.habits.push_back(pair);
        if (fields[0] == "refused") out.refused.push_back(pair);
        if (fields[0] == "word") out.words.push_back(pair);
    }
    return out;
}

enum class Tab { Welcome, Typing, Words, Privacy, Help };
const wchar_t *TabNames[] = {L"Welcome", L"Typing", L"Your words", L"Privacy", L"Help"};

enum class Action { ShowTab, LivePreview, FasterPreview, Refuse, Allow, Forget, ForgetAll, TryIt };

// Something drawn that can be clicked or reached with Tab.
struct Target {
    Gdiplus::RectF box;
    Action action;
    int tab = 0;
    Pair pair;
};

class Window {
public:
    Core core;
    Tab tab = Tab::Typing;
    bool livePreview = true, fasterPreview = true;
    Words words;
    bool demo = false;

    void Reload() {
        if (demo) {
            words = ParseWords("fixes\t9\nhabit\tsawa\t\xD8\xB3\xD9\x88\xD8\xA7\nrefused\ttab\t\xD8\xB7\xD8\xA8\n"
                               "word\tsawa\t\xD8\xB3\xD9\x88\xD8\xA7\t4\nword\theik\t\xD9\x87\xD9\x8A\xD9\x83\t3\n"
                               "word\tla2\t\xD9\x84\xD8\xA3\t2");
            return;
        }
        if (core.settingGet) {
            livePreview = core.settingGet("livePreview") != 0;
            fasterPreview = core.settingGet("fasterPreview") != 0;
        }
        words = Words{};
        if (core.wordsList && core.release) {
            if (char *lines = core.wordsList()) {
                words = ParseWords(lines);
                core.release(lines);
            }
        }
    }

    // Draws the whole window into `graphics` (a client area of `size`), and notes what can be clicked.
    void Draw(Gdiplus::Graphics &graphics, SIZE size) {
        colours_ = Colours();
        graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
        graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
        graphics.Clear(Colour(colours_.surface));
        targets_.clear();
        g_ = &graphics;
        const float left = S(24), width = static_cast<float>(size.cx) - 2 * left;

        Gdiplus::Font title(LatinFamily(), S(22), Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
        Text(L"Harfi", title, colours_.text, left, S(20), width);
        Gdiplus::Font arabic(ArabicFamily(), S(17), 0, Gdiplus::UnitPixel);
        Write(graphics, L"\x062D\x0631\x0641\x064A", arabic, colours_.muted,  // حرفي
              Gdiplus::RectF(left + width - S(60), S(22), S(60), S(28)), true);

        // The tabs: a row of pills, the chosen one on soft cedar.
        Gdiplus::Font tabFont(LatinFamily(), S(14), 0, Gdiplus::UnitPixel);
        float x = left;
        for (int i = 0; i < 5; ++i) {
            float w = Measure(TabNames[i], tabFont, false).Width + S(24);
            Gdiplus::RectF pill(x, S(62), w, S(30));
            bool chosen = static_cast<int>(tab) == i;
            if (chosen) Fill(pill, S(8), colours_.accentSoft);
            Write(graphics, TabNames[i], tabFont, chosen ? colours_.accent : colours_.text, pill, false);
            Add({pill, Action::ShowTab, i, {}});
            x += w + S(4);
        }

        // The tab's cards, scrolled inside the rest of the window.
        const float top = S(106), bottom = static_cast<float>(size.cy) - S(16);
        view_ = Gdiplus::RectF(0, top, static_cast<float>(size.cx), bottom - top);
        graphics.SetClip(view_);
        left_ = left;
        width_ = width;
        y_ = top - scroll_;
        switch (tab) {
            case Tab::Welcome: Welcome(); break;
            case Tab::Typing: Typing(); break;
            case Tab::Words: YourWords(); break;
            case Tab::Privacy: Privacy(); break;
            case Tab::Help: Help(); break;
        }
        content_ = y_ + scroll_ - top;
        graphics.ResetClip();

        if (focus_ >= 0 && focus_ < static_cast<int>(targets_.size()) && keyboard_) {  // where Tab is
            Gdiplus::RectF ring = targets_[static_cast<size_t>(focus_)].box;
            ring.Inflate(S(2), S(2));
            Gdiplus::GraphicsPath path;
            RoundedRect(path, ring, S(9));
            Gdiplus::Pen pen(Colour(colours_.accent), S(2));
            graphics.DrawPath(&pen, &path);
        }
        g_ = nullptr;
    }

    float MaxScroll() const { return (std::max)(0.0f, content_ - view_.Height); }

    void Scroll(float by) { scroll_ = std::clamp(scroll_ + by, 0.0f, MaxScroll()); }

    const Target *At(POINT point) const {
        Gdiplus::PointF at(static_cast<float>(point.x), static_cast<float>(point.y));
        for (const Target &target : targets_) {
            if (target.box.Contains(at)) return &target;
        }
        return nullptr;
    }

    // Tab and Shift+Tab move through what can be clicked.
    void Step(int by) {
        keyboard_ = true;
        int count = static_cast<int>(targets_.size());
        if (count == 0) return;
        focus_ = focus_ < 0 ? (by > 0 ? 0 : count - 1) : (focus_ + by + count) % count;
    }

    const Target *Focused() const {
        return keyboard_ && focus_ >= 0 && focus_ < static_cast<int>(targets_.size())
                   ? &targets_[static_cast<size_t>(focus_)] : nullptr;
    }

    void Mouse() { keyboard_ = false; }

    void Show(Tab next) {
        tab = next;
        scroll_ = 0;
        if (focus_ > 4) focus_ = static_cast<int>(next);  // stays on the tab row
    }

private:
    float S(float value) const { return value * scale; }

    void Add(const Target &target) { targets_.push_back(target); }

    void Fill(const Gdiplus::RectF &rect, float radius, COLORREF colour, COLORREF border = CLR_INVALID) {
        FillBox(*g_, rect, radius, colour, border);
    }

    float Text(const std::wstring &text, const Gdiplus::Font &font, COLORREF colour, float x, float y, float width,
               bool draw = true) {
        return WrappedText(*g_, text, font, colour, x, y, width, draw);
    }

    // A white card as tall as what `body` draws in it. `body(draw, x, y, width)` returns its height.
    void Card(const std::function<float(bool, float, float, float)> &body) {
        const float pad = S(14);
        float height = body(false, left_ + pad, y_ + pad, width_ - 2 * pad);
        Fill(Gdiplus::RectF(left_, y_, width_, height + 2 * pad), S(10), colours_.chip, colours_.border);
        body(true, left_ + pad, y_ + pad, width_ - 2 * pad);
        y_ += height + 2 * pad + S(12);
    }

    // A title with a quiet line under it; returns the height.
    float Titled(bool draw, const std::wstring &title, const std::wstring &detail, float x, float y, float width) {
        Gdiplus::Font strong(LatinFamily(), S(15), 0, Gdiplus::UnitPixel);
        Gdiplus::Font quiet(LatinFamily(), S(12.5f), 0, Gdiplus::UnitPixel);
        float height = Text(title, strong, colours_.text, x, y, width, draw);
        if (!detail.empty()) height += S(3) + Text(detail, quiet, colours_.muted, x, y + height + S(3), width, draw);
        return height;
    }

    // A small button whose right edge is at `edge` (its left edge with `fromLeft`); returns its box (drawn only
    // when `draw`).
    Gdiplus::RectF Button(bool draw, const std::wstring &label, float edge, float middle, const Target &target,
                          bool quiet = false, bool fromLeft = false) {
        Gdiplus::Font font(LatinFamily(), S(12.5f), 0, Gdiplus::UnitPixel);
        float w = Measure(label, font, false).Width + S(20), h = S(26);
        Gdiplus::RectF box(fromLeft ? edge : edge - w, middle - h / 2, w, h);
        if (draw) {
            Fill(box, S(8), quiet ? colours_.surface : colours_.accentSoft, quiet ? colours_.border : CLR_INVALID);
            Write(*g_, label, font, quiet ? colours_.muted : colours_.accent, box, false);
            Target placed = target;
            placed.box = box;
            Add(placed);
        }
        return box;
    }

    void Switch(const std::wstring &title, const std::wstring &detail, bool on, Action action) {
        Card([&](bool draw, float x, float y, float width) {
            const float track = S(40), knob = S(22);
            float height = (std::max)(Titled(draw, title, detail, x, y, width - track - S(16)), knob);
            if (draw) {
                Gdiplus::RectF box(x + width - track, y + (height - knob) / 2, track, knob);
                Fill(box, knob / 2, on ? colours_.accent : colours_.accentLine);
                float cx = on ? box.GetRight() - knob + S(3) : box.X + S(3);
                Gdiplus::SolidBrush white(Colour(colours_.chip));
                g_->FillEllipse(&white, cx, box.Y + S(3), knob - S(6), knob - S(6));
                // The whole card is the switch.
                Add({Gdiplus::RectF(left_, y - S(14), width_, height + S(28)), action, 0, {}});
            }
            return height;
        });
    }

    void Welcome() {
        Card([&](bool draw, float x, float y, float width) {
            float height = Titled(draw, L"Welcome. Let's try it once.",
                                  L"Harfi turns the Arabizi you type into Arabic, on this PC. Do these in any app "
                                  L"where you type.", x, y, width);
            Gdiplus::RectF button = Button(draw, L"Open Notepad to try it", x, y + height + S(26),
                                           {{}, Action::TryIt, 0, {}}, false, true);
            return height + S(12) + button.Height + S(2);
        });
        struct Step { const wchar_t *title, *detail; };
        const Step steps[] = {
            {L"Switch to Harfi with Win+Space",
             L"Harfi is the Arabic (Lebanon) keyboard. Win+Space again goes back to your other keyboard."},
            {L"Type kifak, shu 3am ta3mel? and press Enter",
             L"Your text becomes Arabic. Enter again sends it. Ctrl+Z right after brings your Latin back."},
            {L"Type a sentence, then press \x2191 before Enter",
             L"A row of spellings opens on the word Harfi is least sure of. \x2190 \x2192 choose another word, a "
             L"number picks its spelling."},
        };
        Card([&](bool draw, float x, float y, float width) {
            float height = 0;
            Gdiplus::Font number(LatinFamily(), S(13), Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
            for (int i = 0; i < 3; ++i) {
                if (i > 0) {
                    if (draw) Rule(x, y + height + S(10), width);
                    height += S(21);
                }
                if (draw) {
                    Gdiplus::SolidBrush soft(Colour(colours_.accentSoft));
                    g_->FillEllipse(&soft, x, y + height, S(28), S(28));
                    Write(*g_, std::to_wstring(i + 1), number, colours_.accent,
                          Gdiplus::RectF(x, y + height, S(28), S(28)), false);
                }
                height += (std::max)(S(28), Titled(draw, steps[i].title, steps[i].detail, x + S(40), y + height,
                                                 width - S(40)));
            }
            return height;
        });
    }

    void Typing() {
        Switch(L"Live preview", L"A small box above your text shows the Arabic as you type.", livePreview,
               Action::LivePreview);
        Switch(L"Faster preview",
               L"Reuses what is already converted as you type, so the preview and Enter are about twice as fast. "
               L"Now and then a word can come out differently.",
               fasterPreview, Action::FasterPreview);
    }

    void Rule(float x, float y, float width) {
        Gdiplus::Pen pen(Colour(colours_.border), 1);
        g_->DrawLine(&pen, x, y, x + width, y);
    }

    // One word: the typed word on the left, its Arabic and a button on the right. Returns the row's height.
    float Row(bool draw, const Pair &pair, float x, float y, float width, const std::wstring &button, Action action,
              bool crossed) {
        const float height = S(34);
        if (!draw) return height;
        Gdiplus::Font latin(L"Consolas", S(13), 0, Gdiplus::UnitPixel);
        Gdiplus::Font arabic(ArabicFamily(), S(19), 0, Gdiplus::UnitPixel);
        Gdiplus::Font quiet(LatinFamily(), S(12), 0, Gdiplus::UnitPixel);
        float middle = y + height / 2;
        Gdiplus::StringFormat format;
        format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
        Gdiplus::SolidBrush muted(Colour(colours_.muted));
        g_->DrawString(pair.latin.c_str(), static_cast<INT>(pair.latin.size()), &latin,
                       Gdiplus::RectF(x, y, width / 2, height), &format, &muted);
        Gdiplus::RectF box = Button(true, button, x + width, middle, {{}, action, 0, pair}, button == L"\x00D7");
        float right = box.X - S(12);
        float w = Measure(pair.arabic, arabic, true).Width + S(4);
        Write(*g_, pair.arabic, arabic, crossed ? colours_.muted : colours_.text,
              Gdiplus::RectF(right - w, y, w, height), true);
        if (crossed) {
            Gdiplus::Pen pen(Colour(colours_.muted), 1);
            g_->DrawLine(&pen, right - w, middle + S(2), right, middle + S(2));
        }
        if (pair.times > 1) {
            std::wstring times = L"\x00D7" + std::to_wstring(pair.times);
            float tw = Measure(times, quiet, false).Width + S(4);
            Write(*g_, times, quiet, colours_.muted, Gdiplus::RectF(right - w - S(10) - tw, y, tw, height), false);
        }
        return height;
    }

    void YourWords() {
        if (words.words.empty() && words.habits.empty() && words.refused.empty()) {
            Card([&](bool draw, float x, float y, float width) {
                return Titled(draw, L"Teach Harfi your spellings",
                              L"When a word comes out wrong, press \x2191 and pick the right one. Your picks show "
                              L"up here and come first next time.", x, y, width);
            });
            return;
        }
        Gdiplus::Font quiet(LatinFamily(), S(13), 0, Gdiplus::UnitPixel);
        std::wstring summary = std::to_wstring(words.words.size()) + L" words taught \x00B7 " +
                               std::to_wstring(words.fixes) + L" fixes in the last 30 days";
        y_ += Text(summary, quiet, colours_.muted, left_, y_, width_) + S(10);
        if (!words.habits.empty() || !words.refused.empty()) {
            Card([&](bool draw, float x, float y, float width) {
                float height = Titled(draw, L"Harfi now writes these your way",
                                      L"A word becomes a habit after you pick the same spelling 3 times on 2 "
                                      L"different days.", x, y, width) + S(6);
                for (const Pair &habit : words.habits) {
                    height += Row(draw, habit, x, y + height, width, L"Don't", Action::Refuse, false);
                }
                for (const Pair &habit : words.refused) {
                    height += Row(draw, habit, x, y + height, width, L"Allow again", Action::Allow, true);
                }
                return height;
            });
        }
        if (!words.words.empty()) {
            Card([&](bool draw, float x, float y, float width) {
                float height = 0;
                for (size_t i = 0; i < words.words.size(); ++i) {
                    if (i > 0 && draw) Rule(x, y + height, width);
                    height += Row(draw, words.words[i], x, y + height, width, L"\x00D7", Action::Forget, false);
                }
                return height;
            });
        }
        Button(true, L"Forget all my words", left_, y_ + S(13), {{}, Action::ForgetAll, 0, {}}, true, true);
        y_ += S(38);
    }

    void Privacy() {
        Card([&](bool draw, float x, float y, float width) {
            return Titled(draw, L"Everything happens on your PC",
                          L"What you type is converted on this PC and never sent anywhere.\n\n"
                          L"When you pick a different spelling, Harfi keeps that one word (not the sentence) in an "
                          L"encrypted file on this PC for 30 days, so your spelling comes first next time. You can "
                          L"forget words in Your words.\n\n"
                          L"Password fields are never touched.", x, y, width);
        });
    }

    void Help() {
        struct Key { const wchar_t *key, *what; };
        const Key keys[] = {
            {L"Win+Space", L"Switch between Harfi and your other keyboard."},
            {L"Enter", L"Turn the Latin into Arabic. Enter again sends."},
            {L"\x2191 while typing", L"Fix a word before converting: \x2190 \x2192 the word, 1\x2013" L"7 the spelling."},
            {L"\x2191 right after", L"Fix a word in what was just converted (Alt+Tab too, where Windows allows it)."},
            {L"Spell it", L"In the row of spellings: write the word yourself, letter by letter."},
            {L"Ctrl+Z", L"Right after converting: back to your Latin."},
            {L"Alt+Enter", L"Convert the selected Latin text."},
            {L"Esc", L"Keep the text as typed."},
        };
        Card([&](bool draw, float x, float y, float width) {
            Gdiplus::Font key(LatinFamily(), S(13), Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
            Gdiplus::Font what(LatinFamily(), S(13), 0, Gdiplus::UnitPixel);
            float height = 0;
            for (const Key &row : keys) {
                if (height > 0) height += S(9);
                if (draw) Text(row.key, key, colours_.accent, x, y + height, S(120));
                height += Text(row.what, what, colours_.text, x + S(124), y + height, width - S(124), draw);
            }
            return height;
        });
    }

public:
    float scale = 1;

private:
    Gdiplus::Graphics *g_ = nullptr;
    Palette colours_;
    std::vector<Target> targets_;
    Gdiplus::RectF view_;
    float left_ = 0, width_ = 0, y_ = 0, scroll_ = 0, content_ = 0;
    int focus_ = -1;
    bool keyboard_ = false;
};

Window window;

void Paint(HWND hwnd) {
    PaintBuffered(hwnd, [](Gdiplus::Graphics &graphics, SIZE size) { window.Draw(graphics, size); });
}

void Do(HWND hwnd, const Target &target) {
    Core &core = window.core;
    std::string latin = Narrow(target.pair.latin), arabic = Narrow(target.pair.arabic);
    switch (target.action) {
        case Action::ShowTab: window.Show(static_cast<Tab>(target.tab)); break;
        case Action::LivePreview:
            window.livePreview = !window.livePreview;
            if (core.settingSet) core.settingSet("livePreview", window.livePreview);
            break;
        case Action::FasterPreview:
            window.fasterPreview = !window.fasterPreview;
            if (core.settingSet) core.settingSet("fasterPreview", window.fasterPreview);
            break;
        case Action::Refuse: if (core.wordsRefuse) core.wordsRefuse(latin.c_str(), arabic.c_str()); break;
        case Action::Allow: if (core.wordsAllow) core.wordsAllow(latin.c_str(), arabic.c_str()); break;
        case Action::Forget: if (core.wordsForget) core.wordsForget(latin.c_str(), arabic.c_str()); break;
        case Action::ForgetAll:
            if (MessageBoxW(hwnd, L"Harfi will stop putting your spellings first. This can't be undone.",
                            L"Forget all your words?", MB_OKCANCEL | MB_ICONWARNING | MB_DEFBUTTON2) == IDOK &&
                core.wordsWipe) {
                core.wordsWipe();
            }
            break;
        case Action::TryIt: ShellExecuteW(hwnd, L"open", L"notepad.exe", nullptr, nullptr, SW_SHOWNORMAL); break;
    }
    if (target.action != Action::ShowTab && target.action != Action::TryIt) window.Reload();
    window.Scroll(0);
    InvalidateRect(hwnd, nullptr, FALSE);
}

LRESULT CALLBACK Procedure(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
        case WM_PAINT: Paint(hwnd); return 0;
        case WM_ERASEBKGND: return 1;
        case WM_ACTIVATE:
            if (LOWORD(wParam) != WA_INACTIVE) {  // the keyboard may have learned a word since
                window.Reload();
                InvalidateRect(hwnd, nullptr, FALSE);
            }
            return 0;
        case WM_LBUTTONUP: {
            window.Mouse();
            POINT at = {GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
            if (const Target *target = window.At(at)) {
                Target copy = *target;
                Do(hwnd, copy);
            }
            return 0;
        }
        case WM_SETCURSOR:
            if (LOWORD(lParam) == HTCLIENT) {
                POINT at;
                GetCursorPos(&at);
                ScreenToClient(hwnd, &at);
                SetCursor(LoadCursorW(nullptr, window.At(at) ? IDC_HAND : IDC_ARROW));
                return TRUE;
            }
            break;
        case WM_MOUSEWHEEL:
            window.Scroll(-static_cast<float>(GET_WHEEL_DELTA_WPARAM(wParam)) / WHEEL_DELTA * 48 * window.scale);
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        case WM_KEYDOWN:
            switch (wParam) {
                case VK_TAB: window.Step(GetKeyState(VK_SHIFT) < 0 ? -1 : 1); break;
                case VK_SPACE:
                case VK_RETURN:
                    if (const Target *target = window.Focused()) {
                        Target copy = *target;
                        Do(hwnd, copy);
                    }
                    break;
                case VK_LEFT:
                case VK_RIGHT: {
                    int next = std::clamp(static_cast<int>(window.tab) + (wParam == VK_RIGHT ? 1 : -1), 0, 4);
                    window.Show(static_cast<Tab>(next));
                    break;
                }
                case VK_DOWN: window.Scroll(48 * window.scale); break;
                case VK_UP: window.Scroll(-48 * window.scale); break;
                case VK_ESCAPE: DestroyWindow(hwnd); return 0;
                default: return DefWindowProcW(hwnd, message, wParam, lParam);
            }
            InvalidateRect(hwnd, nullptr, FALSE);
            return 0;
        case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

Tab TabNamed(const std::wstring &name, Tab otherwise) {
    const wchar_t *names[] = {L"welcome", L"typing", L"words", L"privacy", L"help"};
    for (int i = 0; i < 5; ++i) {
        if (name == names[i]) return static_cast<Tab>(i);
    }
    return otherwise;
}
}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    g_module = instance;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    int count = 0;
    wchar_t **arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    std::wstring render;
    for (int i = 1; arguments && i < count; ++i) {
        std::wstring argument = arguments[i];
        if (argument == L"--set" && i + 2 < count) {
            window.core.Load();
            if (!window.core.settingSet) return 2;
            return window.core.settingSet(Narrow(arguments[i + 1]).c_str(), std::wstring(arguments[i + 2]) != L"0")
                       ? 0 : 1;
        }
        if (argument == L"--welcome") window.tab = Tab::Welcome;
        if (argument == L"--demo") window.demo = true;
        if (argument == L"--tab" && i + 1 < count) window.tab = TabNamed(arguments[++i], window.tab);
        if (argument == L"--render" && i + 1 < count) render = arguments[++i];
    }
    LatinFamily();  // starts GDI+

    if (!render.empty()) {  // a picture of the window, for checking the drawing
        window.scale = 1.5f;
        window.Reload();
        SIZE size = {static_cast<LONG>(Width * window.scale), static_cast<LONG>(Height * window.scale)};
        Gdiplus::Bitmap bitmap(size.cx, size.cy, PixelFormat32bppARGB);
        Gdiplus::Graphics graphics(&bitmap);
        window.Draw(graphics, size);
        return SavePng(bitmap, render) ? 0 : 1;
    }

    if (HWND open = FindWindowW(ClassName, nullptr)) {  // one window: the one already open comes to the front
        ShowWindow(open, SW_RESTORE);
        SetForegroundWindow(open);
        return 0;
    }
    window.core.Load();
    window.Reload();

    WNDCLASSEXW type = {sizeof(type)};
    type.lpfnWndProc = Procedure;
    type.hInstance = instance;
    type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    type.lpszClassName = ClassName;
    RegisterClassExW(&type);
    const DWORD style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    UINT dpi = GetDpiForSystem();
    window.scale = static_cast<float>(dpi) / 96;
    RECT frame = {0, 0, MulDiv(Width, static_cast<int>(dpi), 96), MulDiv(Height, static_cast<int>(dpi), 96)};
    AdjustWindowRectExForDpi(&frame, style, FALSE, 0, dpi);
    int w = frame.right - frame.left, h = frame.bottom - frame.top;
    HWND hwnd = CreateWindowExW(0, ClassName, L"Harfi", style, (GetSystemMetrics(SM_CXSCREEN) - w) / 2,
                                (GetSystemMetrics(SM_CYSCREEN) - h) / 2, w, h, nullptr, nullptr, instance, nullptr);
    if (!hwnd) return 1;
    ShowWindow(hwnd, show);
    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return 0;
}

// The shared core (HarfiCoreC.dll), loaded from the text service's folder, and the few JSON fields it returns.
#pragma once
#include <string>
#include <vector>
#include "harfi_core.h"

// What the composer asks the text service to do after a key (harfi_composer_key).
struct Effect {
    std::string effect = "pass";  // pass, consume, update, commit, commitAndPass, suggest, commitAndCompose, ...
    std::wstring marked;          // the underlined text to show
    std::wstring text;            // the text to insert
    int replacingLength = 0;      // restore, suggest: UTF-16 units before the cursor (the converted text) to replace
    std::vector<std::wstring> candidates;  // spellings to offer (the chip row)
    std::wstring word;            // the word being fixed
    bool wordDoubtful = false;    // it looks wrong: amber in the chip row
    int choice = -1;              // the highlighted spelling, -1 for none
    bool spelling = false;        // spelling letter by letter: the chips are letters
    // Fixing before sending (↑ while typing): the preview's words around the chips, the selected one, doubtful ones.
    std::vector<std::wstring> fixingWords;
    int fixingIndex = -1;
    std::vector<int> fixingDoubtful;
    // A pick just made this typed word a habit (ADR 0033), in UTF-8: the keyboard says so once, Esc refuses it.
    std::string learnedLatin, learnedSpelling;
    std::wstring unsureWord;  // sent with a word the model was unsure of (ADR 0034): pointed out once
};

// What the live preview box shows (harfi_preview); `arabic` is empty when nothing shows yet.
struct Preview {
    std::vector<std::wstring> arabic;
    std::wstring latin;  // typed since the last converted word
    std::vector<int> doubtful;
    bool pending = false;  // the engine's conversion is coming: ask again shortly
};

// The shared core (HarfiCoreC.dll and the rules) is loaded once per process and never unloaded: unloading the Swift
// runtime inside an app can hang it, and switching keyboards would read the lexicon again each time. Each text
// service has a composer of its own.
class Core {
public:
    // Loads HarfiCoreC.dll and the rules from `folder` (the first time); ok() is false when either is missing.
    explicit Core(const std::wstring &folder);
    ~Core();
    Core(const Core &) = delete;
    Core &operator=(const Core &) = delete;

    bool ok() const { return composer_ != nullptr; }
    // The composer's answer to one key, as JSON in harfi_core.h.
    Effect Key(const std::string &keyJson);
    // The composer's answer to a spelling (or letter) clicked in the chip row.
    Effect Pick(const std::wstring &candidate);
    // A new, empty composer: the app ended the composition or the typing moved to another field.
    void Reset();
    // The Latin being typed.
    std::wstring Buffer();
    // The preview for the Latin being typed; `whole` after a pause, so the word being typed shows too.
    Preview PreviewOf(const std::wstring &latin, bool whole);
    // The user said no to a learned habit (UTF-8, as in Effect): never applied or announced again.
    void Refuse(const std::string &latin, const std::string &spelling);

private:
    struct Library;  // the DLL's functions and the opened rules, shared by the whole process
    const Library *library_ = nullptr;
    harfi_composer composer_ = nullptr;
    std::string Take(char *reply);  // the reply as a string, freed in the core
    Effect Read(char *reply);
};

// UTF-8 <-> UTF-16 for the Windows APIs.
std::wstring Widen(const std::string &utf8);
std::string Narrow(const std::wstring &utf16);
// One JSON string field (with its escapes decoded), or an empty string; and one JSON array of strings.
std::string JsonString(const std::string &json, const std::string &field);
std::vector<std::string> JsonStrings(const std::string &json, const std::string &field);
std::vector<int> JsonInts(const std::string &json, const std::string &field);
// One JSON number or boolean field, or `otherwise`.
int JsonInt(const std::string &json, const std::string &field, int otherwise);
bool JsonBool(const std::string &json, const std::string &field);
// A JSON string literal for `text`.
std::string JsonQuote(const std::string &text);

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
    std::vector<std::wstring> candidates;  // spellings to offer (the chip row)
    std::wstring word;            // the word being fixed
    int choice = -1;              // the highlighted spelling, -1 for none
    bool spelling = false;        // spelling letter by letter: the chips are letters
};

class Core {
public:
    // Loads HarfiCoreC.dll and the rules from `folder`; ok() is false when either is missing.
    explicit Core(const std::wstring &folder);
    ~Core();
    Core(const Core &) = delete;
    Core &operator=(const Core &) = delete;

    bool ok() const { return composer_ != nullptr; }
    // The composer's answer to one key, as JSON in harfi_core.h.
    Effect Key(const std::string &keyJson);
    // The composer's answer to a spelling (or letter) clicked in the chip row.
    Effect Pick(const std::wstring &candidate);

private:
    void *library_ = nullptr;
    harfi_core core_ = nullptr;
    harfi_composer composer_ = nullptr;
    decltype(&harfi_core_open) open_ = nullptr;
    decltype(&harfi_core_close) close_ = nullptr;
    decltype(&harfi_composer_new) newComposer_ = nullptr;
    decltype(&harfi_composer_free) freeComposer_ = nullptr;
    decltype(&harfi_composer_key) key_ = nullptr;
    decltype(&harfi_composer_pick) pick_ = nullptr;
    Effect Read(char *reply);
    decltype(&harfi_free) free_ = nullptr;
};

// UTF-8 <-> UTF-16 for the Windows APIs.
std::wstring Widen(const std::string &utf8);
std::string Narrow(const std::wstring &utf16);
// One JSON string field (with its escapes decoded), or an empty string; and one JSON array of strings.
std::string JsonString(const std::string &json, const std::string &field);
std::vector<std::string> JsonStrings(const std::string &json, const std::string &field);
// One JSON number or boolean field, or `otherwise`.
int JsonInt(const std::string &json, const std::string &field, int otherwise);
bool JsonBool(const std::string &json, const std::string &field);
// A JSON string literal for `text`.
std::string JsonQuote(const std::string &text);

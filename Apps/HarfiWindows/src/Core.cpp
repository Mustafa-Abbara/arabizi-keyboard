#include "Core.h"
#include <windows.h>
#include <cctype>
#include <cstdlib>

namespace {
template <typename T> T Load(void *library, const char *name) {
    return reinterpret_cast<T>(reinterpret_cast<void *>(GetProcAddress(static_cast<HMODULE>(library), name)));
}

// Reads a JSON string starting at the opening quote `at`; decodes \" \\ \/ \b \f \n \r \t \uXXXX (with pairs).
std::string ReadString(const std::string &json, size_t at, size_t *end) {
    std::string out;
    size_t i = at + 1;
    auto hex = [&](size_t from) { return static_cast<unsigned>(std::stoul(json.substr(from, 4), nullptr, 16)); };
    auto append = [&](unsigned code) {
        if (code < 0x80) { out += static_cast<char>(code); }
        else if (code < 0x800) { out += static_cast<char>(0xC0 | (code >> 6)); out += static_cast<char>(0x80 | (code & 0x3F)); }
        else if (code < 0x10000) {
            out += static_cast<char>(0xE0 | (code >> 12)); out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (code & 0x3F));
        } else {
            out += static_cast<char>(0xF0 | (code >> 18)); out += static_cast<char>(0x80 | ((code >> 12) & 0x3F));
            out += static_cast<char>(0x80 | ((code >> 6) & 0x3F)); out += static_cast<char>(0x80 | (code & 0x3F));
        }
    };
    while (i < json.size() && json[i] != '"') {
        if (json[i] != '\\') { out += json[i++]; continue; }
        char escape = i + 1 < json.size() ? json[i + 1] : '"';
        i += 2;
        switch (escape) {
            case 'b': out += '\b'; break;
            case 'f': out += '\f'; break;
            case 'n': out += '\n'; break;
            case 'r': out += '\r'; break;
            case 't': out += '\t'; break;
            case 'u': {
                if (i + 4 > json.size()) break;
                unsigned code = hex(i);
                i += 4;
                if (code >= 0xD800 && code < 0xDC00 && i + 6 <= json.size() && json[i] == '\\' && json[i + 1] == 'u') {
                    code = 0x10000 + ((code - 0xD800) << 10) + (hex(i + 2) - 0xDC00);
                    i += 6;
                }
                append(code);
                break;
            }
            default: out += escape;  // " \ /
        }
    }
    if (end) *end = i + 1;
    return out;
}

size_t FieldValue(const std::string &json, const std::string &field) {
    size_t at = json.find("\"" + field + "\":");
    return at == std::string::npos ? at : at + field.size() + 3;
}
}  // namespace

std::wstring Widen(const std::string &utf8) {
    if (utf8.empty()) return {};
    int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
    std::wstring out(static_cast<size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), out.data(), size);
    return out;
}

std::string Narrow(const std::wstring &utf16) {
    if (utf16.empty()) return {};
    int size = WideCharToMultiByte(CP_UTF8, 0, utf16.data(), static_cast<int>(utf16.size()), nullptr, 0, nullptr, nullptr);
    std::string out(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, utf16.data(), static_cast<int>(utf16.size()), out.data(), size, nullptr, nullptr);
    return out;
}

std::string JsonString(const std::string &json, const std::string &field) {
    size_t at = FieldValue(json, field);
    if (at == std::string::npos || at >= json.size() || json[at] != '"') return {};
    return ReadString(json, at, nullptr);
}

std::vector<std::string> JsonStrings(const std::string &json, const std::string &field) {
    std::vector<std::string> out;
    size_t at = FieldValue(json, field);
    if (at == std::string::npos || at >= json.size() || json[at] != '[') return out;
    size_t i = at + 1;
    while (i < json.size() && json[i] != ']') {
        if (json[i] == '"') { size_t end = i; out.push_back(ReadString(json, i, &end)); i = end; }
        else { ++i; }
    }
    return out;
}

int JsonInt(const std::string &json, const std::string &field, int otherwise) {
    size_t at = FieldValue(json, field);
    if (at == std::string::npos || at >= json.size() || !(isdigit(static_cast<unsigned char>(json[at])) || json[at] == '-'))
        return otherwise;
    return std::atoi(json.c_str() + at);
}

bool JsonBool(const std::string &json, const std::string &field) {
    size_t at = FieldValue(json, field);
    return at != std::string::npos && json.compare(at, 4, "true") == 0;
}

std::string JsonQuote(const std::string &text) {
    std::string out = "\"";
    for (unsigned char c : text) {
        if (c == '"' || c == '\\') { out += '\\'; out += static_cast<char>(c); }
        else if (c < 0x20) { char buffer[8]; wsprintfA(buffer, "\\u%04x", c); out += buffer; }
        else { out += static_cast<char>(c); }
    }
    return out + "\"";
}

Core::Core(const std::wstring &folder) {
    library_ = LoadLibraryW((folder + L"\\HarfiCoreC.dll").c_str());
    if (!library_) return;
    open_ = Load<decltype(open_)>(library_, "harfi_core_open");
    close_ = Load<decltype(close_)>(library_, "harfi_core_close");
    newComposer_ = Load<decltype(newComposer_)>(library_, "harfi_composer_new");
    freeComposer_ = Load<decltype(freeComposer_)>(library_, "harfi_composer_free");
    key_ = Load<decltype(key_)>(library_, "harfi_composer_key");
    pick_ = Load<decltype(pick_)>(library_, "harfi_composer_pick");
    free_ = Load<decltype(free_)>(library_, "harfi_free");
    if (!open_ || !close_ || !newComposer_ || !freeComposer_ || !key_ || !pick_ || !free_) return;
    core_ = open_(Narrow(folder + L"\\rules").c_str());
    if (core_) composer_ = newComposer_(core_);
}

Core::~Core() {
    if (composer_) freeComposer_(composer_);
    if (core_) close_(core_);
    if (library_) FreeLibrary(static_cast<HMODULE>(library_));
}

Effect Core::Key(const std::string &keyJson) {
    return composer_ ? Read(key_(composer_, keyJson.c_str())) : Effect{};
}

Effect Core::Pick(const std::wstring &candidate) {
    return composer_ ? Read(pick_(composer_, Narrow(candidate).c_str())) : Effect{};
}

Effect Core::Read(char *reply) {
    Effect effect;
    if (!reply) return effect;
    std::string json(reply);
    free_(reply);
    effect.effect = JsonString(json, "effect");
    effect.marked = Widen(JsonString(json, "marked"));
    effect.text = Widen(JsonString(json, "text"));
    for (const auto &candidate : JsonStrings(json, "candidates")) effect.candidates.push_back(Widen(candidate));
    effect.word = Widen(JsonString(json, "word"));
    effect.choice = JsonInt(json, "choice", -1);
    effect.spelling = JsonBool(json, "spelling");
    return effect;
}

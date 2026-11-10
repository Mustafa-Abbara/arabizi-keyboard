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

std::vector<int> JsonInts(const std::string &json, const std::string &field) {
    std::vector<int> out;
    size_t at = FieldValue(json, field);
    if (at == std::string::npos || at >= json.size() || json[at] != '[') return out;
    for (size_t i = at + 1; i < json.size() && json[i] != ']'; ++i) {
        if (!isdigit(static_cast<unsigned char>(json[i]))) continue;
        out.push_back(std::atoi(json.c_str() + i));
        while (i + 1 < json.size() && isdigit(static_cast<unsigned char>(json[i + 1]))) ++i;
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

struct Core::Library {
    harfi_core core = nullptr;  // the rules, opened once
    decltype(&harfi_composer_new) newComposer = nullptr;
    decltype(&harfi_composer_free) freeComposer = nullptr;
    decltype(&harfi_composer_key) key = nullptr;
    decltype(&harfi_composer_pick) pick = nullptr;
    decltype(&harfi_composer_buffer) buffer = nullptr;
    decltype(&harfi_preview) preview = nullptr;  // optional: without it there is no preview box
    decltype(&harfi_habit_refuse) refuse = nullptr;  // optional: without it a habit cannot be refused here
    decltype(&harfi_free) free = nullptr;
};

Core::Core(const std::wstring &folder) {
    // Made once (thread-safe) and never freed, so it is never unloaded, not even when HarfiTIP.dll is.
    static const Library *shared = [&]() -> const Library * {
        // The Swift runtime DLLs next to HarfiCoreC.dll are found there, not on the PATH of the app being typed in.
        HMODULE module = LoadLibraryExW((folder + L"\\HarfiCoreC.dll").c_str(), nullptr,
                                        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
        if (!module) return nullptr;
        auto *library = new Library();
        auto open = Load<decltype(&harfi_core_open)>(module, "harfi_core_open");
        library->newComposer = Load<decltype(library->newComposer)>(module, "harfi_composer_new");
        library->freeComposer = Load<decltype(library->freeComposer)>(module, "harfi_composer_free");
        library->key = Load<decltype(library->key)>(module, "harfi_composer_key");
        library->pick = Load<decltype(library->pick)>(module, "harfi_composer_pick");
        library->buffer = Load<decltype(library->buffer)>(module, "harfi_composer_buffer");
        library->preview = Load<decltype(library->preview)>(module, "harfi_preview");
        library->refuse = Load<decltype(library->refuse)>(module, "harfi_habit_refuse");
        library->free = Load<decltype(library->free)>(module, "harfi_free");
        if (!open || !library->newComposer || !library->freeComposer || !library->key || !library->pick ||
            !library->buffer || !library->free) return nullptr;
        library->core = open(Narrow(folder + L"\\rules").c_str());
        return library->core ? library : nullptr;
    }();
    library_ = shared;
    if (library_) composer_ = library_->newComposer(library_->core);
}

Core::~Core() {
    if (composer_) library_->freeComposer(composer_);
}

Effect Core::Key(const std::string &keyJson) {
    return composer_ ? Read(library_->key(composer_, keyJson.c_str())) : Effect{};
}

Effect Core::Pick(const std::wstring &candidate) {
    return composer_ ? Read(library_->pick(composer_, Narrow(candidate).c_str())) : Effect{};
}

void Core::Reset() {
    if (!composer_) return;
    library_->freeComposer(composer_);
    composer_ = library_->newComposer(library_->core);
}

std::wstring Core::Buffer() {
    return composer_ ? Widen(Take(library_->buffer(composer_))) : std::wstring();
}

Preview Core::PreviewOf(const std::wstring &latin, bool whole) {
    Preview preview;
    if (!library_ || !library_->preview) return preview;
    std::string json = Take(library_->preview(library_->core, Narrow(latin).c_str(), whole ? 1 : 0));
    for (const auto &word : JsonStrings(json, "arabic")) preview.arabic.push_back(Widen(word));
    preview.latin = Widen(JsonString(json, "latin"));
    preview.doubtful = JsonInts(json, "doubtful");
    preview.pending = JsonBool(json, "pending");
    return preview;
}

void Core::Refuse(const std::string &latin, const std::string &spelling) {
    if (library_ && library_->refuse) library_->refuse(library_->core, latin.c_str(), spelling.c_str());
}

std::string Core::Take(char *reply) {
    if (!reply) return {};
    std::string text(reply);
    library_->free(reply);
    return text;
}

Effect Core::Read(char *reply) {
    Effect effect;
    if (!reply) return effect;
    std::string json = Take(reply);
    effect.effect = JsonString(json, "effect");
    if (effect.effect.empty()) effect.effect = "pass";  // a reply without an effect never swallows the key
    effect.marked = Widen(JsonString(json, "marked"));
    effect.text = Widen(JsonString(json, "text"));
    effect.replacingLength = JsonInt(json, "replacingLength", 0);
    for (const auto &candidate : JsonStrings(json, "candidates")) effect.candidates.push_back(Widen(candidate));
    effect.word = Widen(JsonString(json, "word"));
    effect.wordDoubtful = JsonBool(json, "wordDoubtful");
    effect.choice = JsonInt(json, "choice", -1);
    effect.spelling = JsonBool(json, "spelling");
    effect.typed = Widen(JsonString(json, "typed"));
    effect.typedStart = JsonInt(json, "typedStart", -1);
    effect.typedLength = JsonInt(json, "typedLength", 0);
    for (const auto &word : JsonStrings(json, "fixingWords")) effect.fixingWords.push_back(Widen(word));
    effect.fixingIndex = JsonInt(json, "fixingIndex", -1);
    effect.fixingDoubtful = JsonInts(json, "fixingDoubtful");
    effect.learnedLatin = JsonString(json, "learnedLatin");
    effect.learnedSpelling = JsonString(json, "learnedSpelling");
    effect.unsureWord = Widen(JsonString(json, "unsureWord"));
    return effect;
}

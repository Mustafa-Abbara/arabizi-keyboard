#include "TextService.h"
#include <InputScope.h>
#include <functional>
#include <new>
#include "DisplayAttribute.h"
#include "Theme.h"

namespace {
// Runs `body` with an edit cookie for a context (read-write or read-only, as requested). It holds the text service and
// the context until it is gone: an asynchronous session can run after the keyboard was switched off or the field
// closed, and its body must still find both.
class EditSession : public ITfEditSession {
public:
    EditSession(IUnknown *service, ITfContext *context, std::function<void(TfEditCookie)> body)
        : service_(service), context_(context), body_(std::move(body)) {
        if (service_) service_->AddRef();
        if (context_) context_->AddRef();
    }
    virtual ~EditSession() {
        if (context_) context_->Release();
        if (service_) service_->Release();
    }
    STDMETHODIMP QueryInterface(REFIID riid, void **object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (riid == IID_IUnknown || riid == IID_ITfEditSession) *object = static_cast<ITfEditSession *>(this);
        if (!*object) return E_NOINTERFACE;
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return static_cast<ULONG>(++references_); }
    STDMETHODIMP_(ULONG) Release() override {
        long left = --references_;
        if (left == 0) delete this;
        return static_cast<ULONG>(left);
    }
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        body_(cookie);
        return S_OK;
    }

private:
    std::atomic<long> references_{1};
    IUnknown *service_;
    ITfContext *context_;
    std::function<void(TfEditCookie)> body_;
};

// GUID_PROP_INPUTSCOPE (InputScope.h), defined here so no extra library is needed.
const GUID InputScopeProperty = {0x1713dd5a, 0x68e7, 0x4a5b, {0x9a, 0xf6, 0x59, 0x2a, 0x59, 0x5c, 0x77, 0x8d}};

bool Down(int key) { return (GetKeyState(key) & 0x8000) != 0; }

// Shift, Ctrl, Alt, Windows and the lock keys on their own type nothing: they never end the word being typed.
bool IsModifier(WPARAM key) {
    switch (key) {
        case VK_SHIFT: case VK_LSHIFT: case VK_RSHIFT: case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL:
        case VK_MENU: case VK_LMENU: case VK_RMENU: case VK_LWIN: case VK_RWIN: case VK_CAPITAL: case VK_NUMLOCK:
        case VK_SCROLL:
            return true;
        default:
            return false;
    }
}

// The character a key types on the US layout, 0 for none. Arabizi is typed with Latin letters, but a keyboard for
// Arabic (Lebanon) runs on the Arabic (101) layout, so the character comes from where the key is (its scan code),
// not from the active layout.
char LatinCharacter(WPARAM wParam, LPARAM lParam) {
    if (wParam >= VK_NUMPAD0 && wParam <= VK_NUMPAD9) return static_cast<char>('0' + (wParam - VK_NUMPAD0));
    switch (wParam) {
        case VK_DECIMAL: return '.';
        case VK_ADD: return '+';
        case VK_SUBTRACT: return '-';
        case VK_MULTIPLY: return '*';
        case VK_DIVIDE: return '/';
        default: break;
    }
    // Scan codes 0x00 to 0x39 of a PC keyboard as US English types them; \x01: the key types nothing.
    static const char Plain[] = "\x01\x01" "1234567890-=" "\x01\x01" "qwertyuiop[]" "\x01\x01" "asdfghjkl;'`" "\x01"
                                "\\" "zxcvbnm,./" "\x01\x01\x01" " ";
    static const char Shifted[] = "\x01\x01" "!@#$%^&*()_+" "\x01\x01" "QWERTYUIOP{}" "\x01\x01" "ASDFGHJKL:\"~" "\x01"
                                  "|" "ZXCVBNM<>?" "\x01\x01\x01" " ";
    static_assert(sizeof(Plain) == 0x3B && sizeof(Shifted) == 0x3B, "one character per scan code up to Space");
    bool shift = Down(VK_SHIFT);
    UINT scan = (static_cast<UINT>(lParam) >> 16) & 0xFF;
    bool extended = (lParam & (1 << 24)) != 0;
    char typed = 0;
    if (!extended && scan < sizeof(Plain) - 1) typed = (shift ? Shifted : Plain)[scan];
    else if (!extended && scan == 0x56) typed = shift ? '|' : '\\';  // the extra key of ISO keyboards
    if (typed == '\x01') typed = 0;
    if (!typed && scan == 0) {  // sent without a scan code (on-screen keyboards, other tools): the virtual key
        if (wParam >= 'A' && wParam <= 'Z') typed = static_cast<char>(shift ? wParam : wParam - 'A' + 'a');
        else if (wParam >= '0' && wParam <= '9' && !shift) typed = static_cast<char>(wParam);
        else if (wParam == VK_SPACE) typed = ' ';
    }
    if ((GetKeyState(VK_CAPITAL) & 1) != 0) {
        if (typed >= 'a' && typed <= 'z') typed = static_cast<char>(typed - 'a' + 'A');
        else if (typed >= 'A' && typed <= 'Z') typed = static_cast<char>(typed - 'A' + 'a');
    }
    return typed;
}

// The key as the composer's JSON (harfi_core.h), without the field's context.
std::string KeyJson(WPARAM wParam, LPARAM lParam) {
    bool control = Down(VK_CONTROL), alt = Down(VK_MENU), shift = Down(VK_SHIFT);
    bool windows = Down(VK_LWIN) || Down(VK_RWIN);
    if (control && !alt && wParam == 'Z' && !shift) return R"({"key":"undo"})";
    if (alt && !control && wParam == VK_RETURN) return R"({"key":"convertSelection"})";
    if (alt && !control && wParam == VK_TAB) return R"({"key":"suggest"})";
    if (control || alt || windows) return R"({"key":"other"})";
    switch (wParam) {
        case VK_RETURN: return R"({"key":"enter"})";
        case VK_BACK: return R"({"key":"backspace"})";
        case VK_ESCAPE: return R"({"key":"escape"})";
        case VK_LEFT: return R"({"key":"arrowLeft"})";
        case VK_RIGHT: return R"({"key":"arrowRight"})";
        case VK_UP: return R"({"key":"arrowUp"})";
        case VK_DOWN: return R"({"key":"arrowDown"})";
        case VK_TAB: return shift ? R"({"key":"backtab"})" : R"({"key":"tab"})";
        default: break;
    }
    char typed = LatinCharacter(wParam, lParam);
    if (typed) return R"({"key":"text","text":)" + JsonQuote(std::string(1, typed)) + "}";
    return R"({"key":"other"})";
}

// Whether the field at `range` takes a password or a PIN (its input scope), where Harfi must never compose.
bool IsSecret(ITfContext *context, TfEditCookie cookie, ITfRange *range) {
    ITfReadOnlyProperty *property = nullptr;
    if (FAILED(context->GetAppProperty(InputScopeProperty, &property)) || !property) return false;
    bool secret = false;
    VARIANT value;
    VariantInit(&value);
    if (SUCCEEDED(property->GetValue(cookie, range, &value)) && value.vt == VT_UNKNOWN && value.punkVal) {
        ITfInputScope *scope = nullptr;
        if (SUCCEEDED(value.punkVal->QueryInterface(__uuidof(ITfInputScope), reinterpret_cast<void **>(&scope)))) {
            InputScope *scopes = nullptr;
            UINT count = 0;
            if (SUCCEEDED(scope->GetInputScopes(&scopes, &count)) && scopes) {
                for (UINT i = 0; i < count; ++i) {
                    switch (scopes[i]) {
                        case IS_PASSWORD: case IS_NUMERIC_PASSWORD: case IS_NUMERIC_PIN: case IS_ALPHANUMERIC_PIN:
                        case IS_ALPHANUMERIC_PIN_SET:
                            secret = true;
                            break;
                        default:
                            break;
                    }
                }
                CoTaskMemFree(scopes);
            }
            scope->Release();
        }
    }
    VariantClear(&value);
    property->Release();
    return secret;
}

// How often a tip was shown or a feature used, for this user (HKCU\Software\Harfi), as on the Mac (UserDefaults).
DWORD Counter(const wchar_t *name) {
    DWORD value = 0, size = sizeof(value);
    RegGetValueW(HKEY_CURRENT_USER, L"Software\\Harfi", name, RRF_RT_REG_DWORD, nullptr, &value, &size);
    return value;
}

void Count(const wchar_t *name) {
    DWORD value = Counter(name) + 1;
    RegSetKeyValueW(HKEY_CURRENT_USER, L"Software\\Harfi", name, REG_DWORD, &value, sizeof(value));
}

// The tips stop once they have done their job (the Mac's fixHintTimes, fixHintUses, previewFixUses).
const DWORD FixHintTimes = 5, FixHintUses = 3, PreviewFixUses = 3;
const UINT PreviewPause = 300;    // ms without a key before the word being typed shows in the preview
const UINT PreviewRecheck = 150;  // ms between looks for the model's conversion while it is on its way

// A rectangle that can be a line of text on a screen (apps sometimes report an empty or absurd one).
bool Plausible(const RECT &rect) {
    int height = rect.bottom - rect.top;
    return height > 4 && height < 400 && rect.right >= rect.left && !(rect.left == 0 && rect.top == 0);
}

// The system caret of this thread, in screen coordinates (classic controls have one even without a layout).
bool CaretRect(RECT *rect) {
    GUITHREADINFO info = {sizeof(info)};
    if (!GetGUIThreadInfo(GetCurrentThreadId(), &info) || !info.hwndCaret) return false;
    RECT caret = info.rcCaret;
    MapWindowPoints(info.hwndCaret, nullptr, reinterpret_cast<POINT *>(&caret), 2);
    if (!Plausible(caret)) return false;
    *rect = caret;
    return true;
}
}  // namespace

TextService::TextService() { ++g_objects; }
TextService::~TextService() { --g_objects; }

STDMETHODIMP TextService::QueryInterface(REFIID riid, void **object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (riid == IID_IUnknown || riid == IID_ITfTextInputProcessor || riid == IID_ITfTextInputProcessorEx) {
        *object = static_cast<ITfTextInputProcessorEx *>(this);
    } else if (riid == IID_ITfKeyEventSink) {
        *object = static_cast<ITfKeyEventSink *>(this);
    } else if (riid == IID_ITfCompositionSink) {
        *object = static_cast<ITfCompositionSink *>(this);
    } else if (riid == IID_ITfDisplayAttributeProvider) {
        *object = static_cast<ITfDisplayAttributeProvider *>(this);
    }
    if (!*object) return E_NOINTERFACE;
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) TextService::AddRef() { return static_cast<ULONG>(++references_); }

STDMETHODIMP_(ULONG) TextService::Release() {
    long left = --references_;
    if (left == 0) delete this;
    return static_cast<ULONG>(left);
}

STDMETHODIMP TextService::Activate(ITfThreadMgr *threadMgr, TfClientId clientId) {
    return ActivateEx(threadMgr, clientId, 0);
}

STDMETHODIMP TextService::ActivateEx(ITfThreadMgr *threadMgr, TfClientId clientId, DWORD) {
    threadMgr_ = threadMgr;
    threadMgr_->AddRef();
    clientId_ = clientId;
    core_ = std::make_unique<Core>(ModuleFolder());  // without the core, every key goes to the app unchanged
    DebugLog(core_->ok() ? "ActivateEx core ok" : "ActivateEx core FAILED");
    ITfCategoryMgr *categories = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                reinterpret_cast<void **>(&categories)))) {
        // Apps that run the text services without COM: msctf.dll makes the category manager itself.
        using Create = HRESULT(WINAPI *)(ITfCategoryMgr **);
        HMODULE msctf = GetModuleHandleW(L"msctf.dll");
        auto create = msctf ? reinterpret_cast<Create>(reinterpret_cast<void *>(GetProcAddress(msctf, "TF_CreateCategoryMgr")))
                            : nullptr;
        if (!create || FAILED(create(&categories))) categories = nullptr;
    }
    if (categories) {
        categories->RegisterGUID(GUID_HarfiInput, &inputAtom_);
        categories->Release();
    }
    ITfKeystrokeMgr *keystrokes = nullptr;
    if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void **>(&keystrokes)))) {
        keystrokes->AdviseKeyEventSink(clientId_, static_cast<ITfKeyEventSink *>(this), TRUE);
        keystrokes->Release();
    }
    return S_OK;
}

STDMETHODIMP TextService::Deactivate() {
    DebugLog("Deactivate");
    Forget(true);  // switching to another keyboard keeps what was typed, as Latin
    if (threadMgr_) {
        ITfKeystrokeMgr *keystrokes = nullptr;
        if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void **>(&keystrokes)))) {
            keystrokes->UnadviseKeyEventSink(clientId_);
            keystrokes->Release();
        }
        threadMgr_->Release();
        threadMgr_ = nullptr;
    }
    if (context_) {
        context_->Release();
        context_ = nullptr;
    }
    core_.reset();
    clientId_ = TF_CLIENTID_NULL;
    return S_OK;
}

STDMETHODIMP TextService::OnSetFocus(BOOL) { return S_OK; }

void TextService::Follow(ITfContext *context) {
    if (context == context_) return;
    Forget(false);
    if (context_) context_->Release();
    context_ = context;
    context_->AddRef();
}

void TextService::Forget(bool sync) {
    if (composition_ && context_) {
        ITfComposition *open = composition_;
        ITfContext *field = context_;
        composition_ = nullptr;
        auto *session = new EditSession(static_cast<ITfTextInputProcessorEx *>(this), field,
                                        [this, open, field](TfEditCookie cookie) {
            ITfRange *range = nullptr;
            if (SUCCEEDED(open->GetRange(&range))) {
                Underline(field, cookie, range, false);
                range->Release();
            }
            open->EndComposition(cookie);
            open->Release();
        });
        HRESULT result = S_OK;
        if (FAILED(field->RequestEditSession(clientId_, session,
                                             (sync ? TF_ES_SYNC : TF_ES_ASYNCDONTCARE) | TF_ES_READWRITE, &result)) ||
            FAILED(result)) {  // the session never ran: let go of the composition it held
            open->Release();
        }
        session->Release();
    } else if (composition_) {
        composition_->Release();
        composition_ = nullptr;
    }
    if (lastCommitEnd_) {
        lastCommitEnd_->Release();
        lastCommitEnd_ = nullptr;
    }
    chips_.Hide();
    preview_.CancelPause();
    preview_.Hide();
    if (core_) core_->Reset();
}

TextService::Field TextService::ReadField(ITfContext *context, bool wantSelection) {
    Field field;
    auto *session = new EditSession(static_cast<ITfTextInputProcessorEx *>(this), context, [&](TfEditCookie cookie) {
        TF_SELECTION selection = {};
        ULONG fetched = 0;
        if (FAILED(context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched)) || fetched != 1) {
            return;
        }
        BOOL empty = TRUE;
        selection.range->IsEmpty(cookie, &empty);
        if (empty && lastCommitEnd_ && !composition_) {
            BOOL same = FALSE;
            lastCommitEnd_->IsEqualStart(cookie, selection.range, TF_ANCHOR_START, &same);
            field.atLastConversion = same != FALSE;
        }
        if (wantSelection && !empty) {
            WCHAR text[2048];
            ULONG length = 0;
            if (SUCCEEDED(selection.range->GetText(cookie, 0, text, ARRAYSIZE(text), &length))) {
                field.selected.assign(text, length);
            }
        }
        field.secure = IsSecret(context, cookie, selection.range);
        selection.range->Release();
    });
    HRESULT result = S_OK;
    context->RequestEditSession(clientId_, session, TF_ES_SYNC | TF_ES_READ, &result);
    session->Release();
    return field;
}

bool TextService::Decide(ITfContext *context, WPARAM wParam, LPARAM lParam) {
    if (!core_ || !core_->ok() || !context || IsModifier(wParam)) return false;
    Follow(context);
    if (decided_ && decidedKey_ == wParam) return decision_.effect != "pass";  // asked twice for the same key
    if (wParam == VK_ESCAPE && GetTickCount64() < habitUntil_ && core_->Buffer().empty()) {
        // Esc while the tip announces a new habit: the user does not want it.
        core_->Refuse(habitLatin_, habitSpelling_);
        habitUntil_ = 0;
        chips_.Hide();
        decision_ = Effect{};
        decision_.effect = "consume";
        decided_ = true;
        decidedKey_ = wParam;
        return true;
    }
    std::string key = KeyJson(wParam, lParam);
    decidedJson_ = key;
    Field field = ReadField(context, key == R"({"key":"convertSelection"})");
    key.pop_back();  // the closing brace: the field's context goes in the same object
    if (field.secure) key += R"(,"secureInput":true)";
    if (field.atLastConversion) key += R"(,"cursorAtLastConversion":true)";
    if (!field.selected.empty()) key += R"(,"selectedText":)" + JsonQuote(Narrow(field.selected));
    wasComposing_ = !core_->Buffer().empty();
    if (decidedJson_ == R"({"key":"suggest"})") Count(L"fixHintUses");  // Alt+Tab used: the tip is less needed
    decision_ = core_->Key(key + "}");
    if (field.secure && decision_.effect == "pass") {
        // A password or PIN: never composed, but typed as the Latin key, not as the Arabic (101) layout under Harfi.
        std::string typed = JsonString(decidedJson_, "text");
        if (!typed.empty()) {
            decision_ = Effect{};
            decision_.effect = "commit";
            decision_.text = Widen(typed);
        }
    }
    // A key the app keeps gets no OnKeyDown: forget it, so the next press of the same key is asked again.
    decided_ = decision_.effect != "pass";
    decidedKey_ = wParam;
    return decision_.effect != "pass";
}

STDMETHODIMP TextService::OnTestKeyDown(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) {
    if (!loggedKey_) {  // once per activation: keys arrive (and whether there is a text field to write into)
        loggedKey_ = true;
        DebugLog(context ? "first key, with a text field" : "first key, NO text field");
    }
    *eaten = Decide(context, wParam, lParam) ? TRUE : FALSE;
    return S_OK;
}

STDMETHODIMP TextService::OnKeyDown(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) {
    *eaten = Decide(context, wParam, lParam) ? TRUE : FALSE;
    if (*eaten) Apply(context, decision_, decidedJson_);
    decided_ = false;
    // "Insert the text, then let the app have the key" (an arrow or a click key while typing): the text is in, so
    // the same key is sent once more; the composer is empty now and lets it through to the app.
    if (*eaten && decision_.effect == "commitAndPass") Resend(wParam, lParam);
    return S_OK;
}

void TextService::Resend(WPARAM wParam, LPARAM lParam) {
    INPUT keys[2] = {};
    for (INPUT &key : keys) {
        key.type = INPUT_KEYBOARD;
        key.ki.wVk = static_cast<WORD>(wParam);
        key.ki.wScan = static_cast<WORD>((static_cast<UINT>(lParam) >> 16) & 0xFF);
        if (lParam & (1 << 24)) key.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;  // arrows, Home, End...
    }
    keys[1].ki.dwFlags |= KEYEVENTF_KEYUP;
    SendInput(2, keys, sizeof(INPUT));
}

STDMETHODIMP TextService::OnTestKeyUp(ITfContext *, WPARAM, LPARAM, BOOL *eaten) {
    *eaten = FALSE;
    return S_OK;
}

STDMETHODIMP TextService::OnKeyUp(ITfContext *, WPARAM, LPARAM, BOOL *eaten) {
    *eaten = FALSE;
    return S_OK;
}

STDMETHODIMP TextService::OnPreservedKey(ITfContext *, REFGUID, BOOL *eaten) {
    *eaten = FALSE;
    return S_OK;
}

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie cookie, ITfComposition *composition) {
    if (composition_ != composition) return S_OK;
    // The app ended it (a click elsewhere, the focus moved): the Latin stays as typed and the composer starts over.
    ITfRange *range = nullptr;
    if (context_ && SUCCEEDED(composition->GetRange(&range))) {
        Underline(context_, cookie, range, false);
        range->Release();
    }
    composition_->Release();
    composition_ = nullptr;
    Forget(false);
    return S_OK;
}

STDMETHODIMP TextService::EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo **attributes) {
    if (!attributes) return E_INVALIDARG;
    *attributes = new (std::nothrow) EnumDisplayAttributes();
    return *attributes ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP TextService::GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo **info) {
    if (!info) return E_INVALIDARG;
    *info = nullptr;
    if (guid != GUID_HarfiInput) return E_INVALIDARG;
    *info = new (std::nothrow) InputAttribute();
    return *info ? S_OK : E_OUTOFMEMORY;
}

void TextService::Apply(ITfContext *context, const Effect &effect, const std::string &key, bool duringKey) {
    if (!context) return;
    auto *session = new EditSession(static_cast<ITfTextInputProcessorEx *>(this), context,
                                    [this, context, effect, key](TfEditCookie cookie) {
        if (lastCommitEnd_) {  // only the text inserted by this very effect counts as the last conversion
            lastCommitEnd_->Release();
            lastCommitEnd_ = nullptr;
        }
        const std::string &kind = effect.effect;
        if (kind == "update" || kind == "suggest" || kind == "restore") {
            SetComposition(context, cookie, effect.marked, effect.replacingLength);
        } else if (kind == "commit" || kind == "commitAndPass" || kind == "replaceSelection") {
            Commit(context, cookie, effect.text);
        } else if (kind == "commitAndCompose") {
            Commit(context, cookie, effect.text);
            SetComposition(context, cookie, effect.marked, 0);
        }
        UpdateBoxes(context, cookie, effect, key);
    });
    HRESULT result = S_OK;
    context->RequestEditSession(clientId_, session, (duringKey ? TF_ES_SYNC : TF_ES_ASYNCDONTCARE) | TF_ES_READWRITE,
                                &result);
    session->Release();
}

void TextService::UpdateBoxes(ITfContext *context, TfEditCookie cookie, const Effect &effect, const std::string &key) {
    const std::string &kind = effect.effect;
    if (kind == "consume" || kind == "pass" || !core_) return;  // nothing changed on screen
    if (kind == "suggest") {
        // Fixing a word. Before sending (↑), the preview stays where it was with the word highlighted, and the chips
        // rise just above it; after a conversion (Alt+Tab), the chips sit above the text.
        preview_.CancelPause();
        RECT above = TextRect(context, cookie);
        if (!effect.fixingWords.empty()) {
            above = preview_.Show(effect.fixingWords, effect.fixingDoubtful, effect.fixingIndex, L"", L"", above);
            if (key == R"({"key":"arrowUp"})" && wasComposing_) Count(L"previewFixUses");
        } else {
            preview_.Hide();
        }
        if (!effect.candidates.empty() || effect.spelling) {
            chips_.Show(
                effect, above,
                [this](const std::wstring &candidate) {  // a chip clicked: the same as its number key
                    if (core_ && context_) Apply(context_, core_->Pick(candidate), {}, false);
                },
                [this] {  // "Spell it": the same as Alt+Tab a second time
                    if (core_ && context_) Apply(context_, core_->Key(R"({"key":"suggest"})"), {}, false);
                });
        } else {
            chips_.Hide();
        }
        return;
    }
    chips_.Hide();
    habitUntil_ = 0;  // a tip on screen is gone with the next change
    if (kind == "update") {
        ShowPreview(context, cookie, false);
        RefreshPreviewAfter(PreviewPause, true);  // after a pause, the word being typed shows too
    } else {
        preview_.CancelPause();
        if (core_->Buffer().empty()) preview_.Hide();
        else ShowPreview(context, cookie, false);
    }
    // A pick just made a typed word a habit (ADR 0033): say so, with Esc to refuse it while the tip is up.
    if (!effect.learnedSpelling.empty()) {
        const UINT shown = 6000;
        habitLatin_ = effect.learnedLatin;
        habitSpelling_ = effect.learnedSpelling;
        habitUntil_ = GetTickCount64() + shown;
        chips_.ShowHint(L"Harfi will now write " + Widen(effect.learnedLatin) + L" as " +
                            Widen(effect.learnedSpelling) + L"  ·  Esc: don't",
                        TextRect(context, cookie), shown);
        return;
    }
    // Sent with a word the model was unsure of (ADR 0034): point at it, every time there is one, since only the user
    // knows how a word the model never saw is written. Alt+Tab starts on the doubtful word.
    if (key == R"({"key":"enter"})" && kind == "commit" && !effect.unsureWord.empty()) {
        chips_.ShowHint(L"Not sure about " + effect.unsureWord + L"  ·  Alt+Tab to fix it", TextRect(context, cookie),
                        4000);
        return;
    }
    // After a conversion, a one-line tip that Alt+Tab fixes a word: the first few times only, and no more once
    // Alt+Tab has been used a few times.
    if (key == R"({"key":"enter"})" && kind == "commit" && Counter(L"fixHintShown") < FixHintTimes &&
        Counter(L"fixHintUses") < FixHintUses) {
        Count(L"fixHintShown");
        chips_.ShowHint(L"Not quite? Alt+Tab to fix a word", TextRect(context, cookie));
    }
}

void TextService::ShowPreview(ITfContext *context, TfEditCookie cookie, bool whole) {
    std::wstring buffer = core_ ? core_->Buffer() : std::wstring();
    Preview preview = buffer.empty() ? Preview{} : core_->PreviewOf(buffer, whole);
    if (preview.arabic.empty()) {
        preview_.Hide();
        return;
    }
    // Until ↑ has been used a few times, a quiet reminder that a word can be fixed before converting.
    std::wstring hint = preview.latin.empty() && Counter(L"previewFixUses") < PreviewFixUses ? L"↑ fix a word" : L"";
    preview_.Show(preview.arabic, preview.doubtful, -1, preview.latin, hint, TextRect(context, cookie));
    // The rules' Arabic is shown while the model's is on its way: look again shortly.
    if (preview.pending) RefreshPreviewAfter(PreviewRecheck, whole);
}

void TextService::RefreshPreviewAfter(UINT milliseconds, bool whole) {
    preview_.AfterPause(milliseconds, [this, whole] {
        if (!context_ || !composition_) return;
        ITfContext *field = context_;
        auto *session = new EditSession(static_cast<ITfTextInputProcessorEx *>(this), field,
                                        [this, field, whole](TfEditCookie cookie) { ShowPreview(field, cookie, whole); });
        HRESULT result = S_OK;
        field->RequestEditSession(clientId_, session, TF_ES_ASYNCDONTCARE | TF_ES_READ, &result);
        session->Release();
    });
}

RECT TextService::TextRect(ITfContext *context, TfEditCookie cookie) {
    ITfRange *range = nullptr;
    if (composition_) {
        composition_->GetRange(&range);
    } else {
        TF_SELECTION selection = {};
        ULONG fetched = 0;
        if (SUCCEEDED(context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched)) && fetched == 1) {
            range = selection.range;
        }
    }
    RECT rect = {};
    BOOL clipped = FALSE;
    ITfContextView *view = nullptr;
    bool found = range && SUCCEEDED(context->GetActiveView(&view)) &&
                 SUCCEEDED(view->GetTextExt(cookie, range, &rect, &clipped)) && Plausible(rect);
    if (view) view->Release();
    if (range) range->Release();
    if (!found) found = CaretRect(&rect);  // apps without a layout yet (TF_E_NOLAYOUT) still have a caret
    if (found) {
        lastRect_ = rect;
        hasLastRect_ = true;
        return rect;
    }
    if (hasLastRect_) return lastRect_;
    POINT mouse = {};
    GetCursorPos(&mouse);
    return {mouse.x, mouse.y, mouse.x, mouse.y + Scaled(20)};
}

void TextService::Underline(ITfContext *context, TfEditCookie cookie, ITfRange *range, bool on) {
    ITfProperty *property = nullptr;
    if (FAILED(context->GetProperty(GUID_PROP_ATTRIBUTE, &property))) return;
    if (on && inputAtom_ != TF_INVALID_GUIDATOM) {
        VARIANT value;
        value.vt = VT_I4;
        value.lVal = static_cast<LONG>(inputAtom_);
        property->SetValue(cookie, range, &value);
    } else {
        property->Clear(cookie, range);
    }
    property->Release();
}

// Shows `text` underlined at the cursor, starting a composition if there is none; it takes the place of the
// `replacingLength` UTF-16 units before the cursor (the converted text, for Ctrl+Z and Alt+Tab). An empty `text`
// ends the composition, so the app never holds an empty one.
void TextService::SetComposition(ITfContext *context, TfEditCookie cookie, const std::wstring &text,
                                 int replacingLength) {
    if (text.empty()) {
        Commit(context, cookie, text);
        return;
    }
    if (!composition_) {
        ITfRange *range = nullptr;
        if (replacingLength > 0) {
            TF_SELECTION selection = {};
            ULONG fetched = 0;
            if (SUCCEEDED(context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched)) && fetched == 1) {
                range = selection.range;
                LONG moved = 0;
                range->ShiftStart(cookie, -replacingLength, &moved, nullptr);
            }
        } else {
            ITfInsertAtSelection *insert = nullptr;
            if (SUCCEEDED(context->QueryInterface(IID_ITfInsertAtSelection, reinterpret_cast<void **>(&insert)))) {
                insert->InsertTextAtSelection(cookie, TF_IAS_QUERYONLY, nullptr, 0, &range);
                insert->Release();
            }
        }
        ITfContextComposition *compositions = nullptr;
        if (range &&
            SUCCEEDED(context->QueryInterface(IID_ITfContextComposition, reinterpret_cast<void **>(&compositions)))) {
            compositions->StartComposition(cookie, range, static_cast<ITfCompositionSink *>(this), &composition_);
            compositions->Release();
        }
        if (range) range->Release();
        if (!composition_) return;
    }
    ITfRange *range = nullptr;
    if (FAILED(composition_->GetRange(&range))) return;
    range->SetText(cookie, 0, text.c_str(), static_cast<LONG>(text.size()));
    Underline(context, cookie, range, true);
    range->Collapse(cookie, TF_ANCHOR_END);  // the cursor after the text
    TF_SELECTION selection = {};
    selection.range = range;
    selection.style.ase = TF_AE_NONE;
    selection.style.fInterimChar = FALSE;
    context->SetSelection(cookie, 1, &selection);
    range->Release();
}

// Inserts `text` in place of the composition (or at the cursor, over any selection) and ends the composition.
// Remembers where the text ends, so the next key can tell whether the cursor is still there.
void TextService::Commit(ITfContext *context, TfEditCookie cookie, const std::wstring &text) {
    ITfRange *end = nullptr;
    if (composition_) {
        ITfRange *range = nullptr;
        if (SUCCEEDED(composition_->GetRange(&range))) {
            range->SetText(cookie, 0, text.c_str(), static_cast<LONG>(text.size()));
            Underline(context, cookie, range, false);
            range->Collapse(cookie, TF_ANCHOR_END);
            TF_SELECTION selection = {};
            selection.range = range;
            context->SetSelection(cookie, 1, &selection);
            end = range;
        }
        composition_->EndComposition(cookie);
        composition_->Release();
        composition_ = nullptr;
    } else if (!text.empty()) {
        ITfInsertAtSelection *insert = nullptr;
        if (SUCCEEDED(context->QueryInterface(IID_ITfInsertAtSelection, reinterpret_cast<void **>(&insert)))) {
            if (SUCCEEDED(insert->InsertTextAtSelection(cookie, 0, text.c_str(), static_cast<LONG>(text.size()), &end))) {
                end->Collapse(cookie, TF_ANCHOR_END);
            }
            insert->Release();
        }
    }
    if (!end) return;
    if (!text.empty() && SUCCEEDED(end->Clone(&lastCommitEnd_))) {
        lastCommitEnd_->SetGravity(cookie, TF_GRAVITY_BACKWARD, TF_GRAVITY_BACKWARD);  // stays right after the text
    }
    end->Release();
}

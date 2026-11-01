#include "TextService.h"
#include <functional>

namespace {
// Runs `body` with a read-write edit cookie for `context`, synchronously.
class EditSession : public ITfEditSession {
public:
    explicit EditSession(std::function<void(TfEditCookie)> body) : body_(std::move(body)) {}
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
    std::function<void(TfEditCookie)> body_;
};

bool Down(int key) { return (GetKeyState(key) & 0x8000) != 0; }

// The key as the composer's JSON (harfi_core.h), from the virtual key and the keyboard state.
std::string KeyJson(WPARAM wParam, LPARAM lParam) {
    bool control = Down(VK_CONTROL), alt = Down(VK_MENU), shift = Down(VK_SHIFT);
    if (control && !alt && wParam == 'Z' && !shift) return R"({"key":"undo"})";
    if (alt && !control && wParam == VK_RETURN) return R"({"key":"convertSelection"})";
    if (alt && !control && wParam == VK_TAB) return R"({"key":"suggest"})";
    if (control || alt) return R"({"key":"other"})";
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
    BYTE state[256] = {};
    if (!GetKeyboardState(state)) return R"({"key":"other"})";
    WCHAR typed[4] = {};
    UINT scan = (static_cast<UINT>(lParam) >> 16) & 0xFF;
    int count = ToUnicode(static_cast<UINT>(wParam), scan, state, typed, 4, 0);
    if (count == 1 && typed[0] >= 0x20 && typed[0] <= 0x7E) {
        return R"({"key":"text","text":)" + JsonQuote(std::string(1, static_cast<char>(typed[0]))) + "}";
    }
    return R"({"key":"other"})";
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
    ITfKeystrokeMgr *keystrokes = nullptr;
    if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void **>(&keystrokes)))) {
        keystrokes->AdviseKeyEventSink(clientId_, static_cast<ITfKeyEventSink *>(this), TRUE);
        keystrokes->Release();
    }
    return S_OK;
}

STDMETHODIMP TextService::Deactivate() {
    if (threadMgr_) {
        ITfKeystrokeMgr *keystrokes = nullptr;
        if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void **>(&keystrokes)))) {
            keystrokes->UnadviseKeyEventSink(clientId_);
            keystrokes->Release();
        }
        threadMgr_->Release();
        threadMgr_ = nullptr;
    }
    if (composition_) {
        composition_->Release();
        composition_ = nullptr;
    }
    core_.reset();
    clientId_ = TF_CLIENTID_NULL;
    return S_OK;
}

STDMETHODIMP TextService::OnSetFocus(BOOL) { return S_OK; }

bool TextService::Decide(WPARAM wParam, LPARAM lParam) {
    if (!core_ || !core_->ok()) return false;
    if (decided_ && decidedKey_ == wParam) return decision_.effect != "pass";  // asked twice for the same key
    decision_ = core_->Key(KeyJson(wParam, lParam));
    // A key the app keeps gets no OnKeyDown: forget it, so the next press of the same key is asked again.
    decided_ = decision_.effect != "pass";
    decidedKey_ = wParam;
    // commitAndPass inserts the text and lets the app have the key: the text is inserted here and the key eaten,
    // so it reaches the app only on the next press (to refine with the per-app checks, ADR 0032 task 3).
    return decision_.effect != "pass";
}

STDMETHODIMP TextService::OnTestKeyDown(ITfContext *, WPARAM wParam, LPARAM lParam, BOOL *eaten) {
    *eaten = Decide(wParam, lParam) ? TRUE : FALSE;
    return S_OK;
}

STDMETHODIMP TextService::OnKeyDown(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) {
    *eaten = Decide(wParam, lParam) ? TRUE : FALSE;
    if (*eaten) Apply(context, decision_);
    decided_ = false;
    return S_OK;
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

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie, ITfComposition *composition) {
    if (composition_ == composition) {
        composition_->Release();
        composition_ = nullptr;
    }
    return S_OK;
}

void TextService::Apply(ITfContext *context, const Effect &effect) {
    if (!context) return;
    auto *session = new EditSession([&](TfEditCookie cookie) {
        const std::string &kind = effect.effect;
        if (kind == "update" || kind == "suggest" || kind == "restore") {
            SetComposition(context, cookie, effect.marked);
        } else if (kind == "commit" || kind == "commitAndPass" || kind == "replaceSelection") {
            Commit(context, cookie, effect.text);
        } else if (kind == "commitAndCompose") {
            Commit(context, cookie, effect.text);
            SetComposition(context, cookie, effect.marked);
        }
    });
    HRESULT result = S_OK;
    context->RequestEditSession(clientId_, session, TF_ES_SYNC | TF_ES_READWRITE, &result);
    session->Release();
}

// Shows `text` underlined at the cursor, starting a composition if there is none.
void TextService::SetComposition(ITfContext *context, TfEditCookie cookie, const std::wstring &text) {
    if (!composition_) {
        ITfInsertAtSelection *insert = nullptr;
        ITfContextComposition *compositions = nullptr;
        ITfRange *range = nullptr;
        if (SUCCEEDED(context->QueryInterface(IID_ITfInsertAtSelection, reinterpret_cast<void **>(&insert))) &&
            SUCCEEDED(insert->InsertTextAtSelection(cookie, TF_IAS_QUERYONLY, nullptr, 0, &range)) &&
            SUCCEEDED(context->QueryInterface(IID_ITfContextComposition, reinterpret_cast<void **>(&compositions)))) {
            compositions->StartComposition(cookie, range, static_cast<ITfCompositionSink *>(this), &composition_);
        }
        if (range) range->Release();
        if (compositions) compositions->Release();
        if (insert) insert->Release();
        if (!composition_) return;
    }
    ITfRange *range = nullptr;
    if (FAILED(composition_->GetRange(&range))) return;
    range->SetText(cookie, 0, text.c_str(), static_cast<LONG>(text.size()));
    range->Collapse(cookie, TF_ANCHOR_END);  // the cursor after the text
    TF_SELECTION selection = {};
    selection.range = range;
    selection.style.ase = TF_AE_NONE;
    selection.style.fInterimChar = FALSE;
    context->SetSelection(cookie, 1, &selection);
    range->Release();
}

// Inserts `text` in place of the composition (or at the cursor) and ends the composition.
void TextService::Commit(ITfContext *context, TfEditCookie cookie, const std::wstring &text) {
    if (composition_) {
        ITfRange *range = nullptr;
        if (SUCCEEDED(composition_->GetRange(&range))) {
            range->SetText(cookie, 0, text.c_str(), static_cast<LONG>(text.size()));
            range->Collapse(cookie, TF_ANCHOR_END);
            TF_SELECTION selection = {};
            selection.range = range;
            context->SetSelection(cookie, 1, &selection);
            range->Release();
        }
        composition_->EndComposition(cookie);
        composition_->Release();
        composition_ = nullptr;
        return;
    }
    ITfInsertAtSelection *insert = nullptr;
    if (SUCCEEDED(context->QueryInterface(IID_ITfInsertAtSelection, reinterpret_cast<void **>(&insert)))) {
        ITfRange *range = nullptr;
        if (SUCCEEDED(insert->InsertTextAtSelection(cookie, 0, text.c_str(), static_cast<LONG>(text.size()), &range))) {
            range->Release();
        }
        insert->Release();
    }
}

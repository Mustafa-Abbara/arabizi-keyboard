#include "LangBar.h"
#include <olectl.h>
#include <shellapi.h>

namespace {
// GUID_LBI_INPUTMODE (ctffunc.h): the language bar item Windows shows in the taskbar's input indicator.
constexpr GUID InputMode = {0x2c77a81e, 0x41cc, 0x4178, {0xa3, 0xa7, 0x5f, 0x8a, 0x98, 0x75, 0x68, 0xe6}};
const wchar_t Description[] = L"Harfi";
const DWORD SinkCookie = 1;  // one sink at a time
}  // namespace

LangBarButton::LangBarButton() { ++g_objects; }

LangBarButton::~LangBarButton() {
    if (sink_) sink_->Release();
    --g_objects;
}

STDMETHODIMP LangBarButton::QueryInterface(REFIID riid, void **object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfLangBarItem) ||
        IsEqualIID(riid, IID_ITfLangBarItemButton)) {
        *object = static_cast<ITfLangBarItemButton *>(this);
    } else if (IsEqualIID(riid, IID_ITfSource)) {
        *object = static_cast<ITfSource *>(this);
    } else {
        return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) LangBarButton::AddRef() { return static_cast<ULONG>(InterlockedIncrement(&references_)); }

STDMETHODIMP_(ULONG) LangBarButton::Release() {
    long left = InterlockedDecrement(&references_);
    if (left == 0) delete this;
    return static_cast<ULONG>(left);
}

STDMETHODIMP LangBarButton::GetInfo(TF_LANGBARITEMINFO *info) {
    if (!info) return E_INVALIDARG;
    info->clsidService = CLSID_HarfiTextService;
    info->guidItem = InputMode;
    info->dwStyle = TF_LBI_STYLE_BTN_BUTTON | TF_LBI_STYLE_SHOWNINTRAY;
    info->ulSort = 0;
    lstrcpynW(info->szDescription, Description, TF_LBI_DESC_MAXLEN);
    return S_OK;
}

STDMETHODIMP LangBarButton::GetStatus(DWORD *status) {
    if (!status) return E_INVALIDARG;
    *status = 0;
    return S_OK;
}

STDMETHODIMP LangBarButton::GetTooltipString(BSTR *tooltip) {
    if (!tooltip) return E_INVALIDARG;
    *tooltip = SysAllocString(L"Harfi: Arabizi to Arabic (click for settings)");
    return *tooltip ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LangBarButton::OnClick(TfLBIClick, POINT, const RECT *) {
    std::wstring app = ModuleFolder() + L"\\harfi-settings.exe";
    ShellExecuteW(nullptr, L"open", app.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    return S_OK;
}

STDMETHODIMP LangBarButton::GetIcon(HICON *icon) {
    if (!icon) return E_INVALIDARG;
    // The caller destroys it. The Harfi icon (harfi.rc), at the size of the taskbar's small icons.
    *icon = static_cast<HICON>(LoadImageW(g_module, MAKEINTRESOURCEW(1), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                                          GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
    return *icon ? S_OK : E_FAIL;
}

STDMETHODIMP LangBarButton::GetText(BSTR *text) {
    if (!text) return E_INVALIDARG;
    *text = SysAllocString(Description);
    return *text ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LangBarButton::AdviseSink(REFIID riid, IUnknown *sink, DWORD *cookie) {
    if (!sink || !cookie) return E_INVALIDARG;
    if (!IsEqualIID(riid, IID_ITfLangBarItemSink)) return CONNECT_E_CANNOTCONNECT;
    if (sink_) return CONNECT_E_ADVISELIMIT;
    if (FAILED(sink->QueryInterface(IID_ITfLangBarItemSink, reinterpret_cast<void **>(&sink_)))) {
        sink_ = nullptr;
        return E_NOINTERFACE;
    }
    *cookie = SinkCookie;
    return S_OK;
}

STDMETHODIMP LangBarButton::UnadviseSink(DWORD cookie) {
    if (cookie != SinkCookie || !sink_) return CONNECT_E_NOCONNECTION;
    sink_->Release();
    sink_ = nullptr;
    return S_OK;
}

LangBarButton *AddLangBarButton(ITfThreadMgr *threadMgr) {
    if (!threadMgr) return nullptr;
    ITfLangBarItemMgr *items = nullptr;
    if (FAILED(threadMgr->QueryInterface(IID_ITfLangBarItemMgr, reinterpret_cast<void **>(&items)))) return nullptr;
    auto *button = new LangBarButton();
    if (FAILED(items->AddItem(button))) {
        button->Release();
        button = nullptr;
    }
    items->Release();
    return button;
}

void RemoveLangBarButton(ITfThreadMgr *threadMgr, LangBarButton *button) {
    if (!button) return;
    ITfLangBarItemMgr *items = nullptr;
    if (threadMgr && SUCCEEDED(threadMgr->QueryInterface(IID_ITfLangBarItemMgr, reinterpret_cast<void **>(&items)))) {
        items->RemoveItem(button);
        items->Release();
    }
    button->Release();
}

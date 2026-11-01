// The DLL's COM entry points: the class factory that makes the text service, and unloading.
#include <new>
#include "Globals.h"
#include "TextService.h"

HINSTANCE g_module = nullptr;
std::atomic<long> g_objects{0};

std::wstring ModuleFolder() {
    wchar_t path[MAX_PATH] = {};
    DWORD length = GetModuleFileNameW(g_module, path, MAX_PATH);
    std::wstring folder(path, length);
    size_t slash = folder.find_last_of(L"\\/");
    return slash == std::wstring::npos ? folder : folder.substr(0, slash);
}

namespace {
class ClassFactory : public IClassFactory {
public:
    STDMETHODIMP QueryInterface(REFIID riid, void **object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (riid == IID_IUnknown || riid == IID_IClassFactory) *object = static_cast<IClassFactory *>(this);
        if (!*object) return E_NOINTERFACE;
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return 2; }  // one static instance
    STDMETHODIMP_(ULONG) Release() override { return 1; }
    STDMETHODIMP CreateInstance(IUnknown *outer, REFIID riid, void **object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (outer) return CLASS_E_NOAGGREGATION;
        auto *service = new (std::nothrow) TextService();
        if (!service) return E_OUTOFMEMORY;
        HRESULT result = service->QueryInterface(riid, object);
        service->Release();
        return result;
    }
    STDMETHODIMP LockServer(BOOL lock) override {
        if (lock) ++g_objects; else --g_objects;
        return S_OK;
    }
};

ClassFactory g_factory;
}  // namespace

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_module = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void **object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (clsid != CLSID_HarfiTextService) return CLASS_E_CLASSNOTAVAILABLE;
    return g_factory.QueryInterface(riid, object);
}

STDAPI DllCanUnloadNow() { return g_objects == 0 ? S_OK : S_FALSE; }

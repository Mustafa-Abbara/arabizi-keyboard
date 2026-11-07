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

void DebugLog(const char *event) {
    DWORD on = 0, size = sizeof(on);
    if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Harfi", L"DebugLog", RRF_RT_REG_DWORD, nullptr, &on, &size) !=
            ERROR_SUCCESS || !on) return;
    wchar_t folder[MAX_PATH] = {};
    ExpandEnvironmentStringsW(L"%LOCALAPPDATA%\\Harfi\\debug.log", folder, MAX_PATH);
    HANDLE file = CreateFileW(folder, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    char app[MAX_PATH] = {};
    GetModuleFileNameA(nullptr, app, MAX_PATH);
    const char *name = app;
    for (const char *c = app; *c; ++c) if (*c == '\\') name = c + 1;
    SYSTEMTIME now;
    GetLocalTime(&now);
    char line[512];
    int length = wsprintfA(line, "%02d:%02d:%02d.%03d %s pid=%lu tid=%lu %s\r\n", now.wHour, now.wMinute, now.wSecond,
                           now.wMilliseconds, name, GetCurrentProcessId(), GetCurrentThreadId(), event);
    DWORD written = 0;
    WriteFile(file, line, static_cast<DWORD>(length), &written, nullptr);
    CloseHandle(file);
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
        DebugLog("CreateInstance");
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
        DebugLog("loaded");
    }
    return TRUE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void **object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    DebugLog("DllGetClassObject");
    if (clsid != CLSID_HarfiTextService) return CLASS_E_CLASSNOTAVAILABLE;
    return g_factory.QueryInterface(riid, object);
}

// Never: the keyboard keeps the shared core and the Swift runtime loaded for the life of the app (Core.h), and
// its window classes must not outlive their code.
STDAPI DllCanUnloadNow() { return S_FALSE; }

// Registration (regsvr32 HarfiTIP.dll): the COM class for the current user, and the keyboard profile and
// categories with Windows' text services. Whether the profile can be registered without admin rights is checked on
// a real machine (ADR 0032 decision 5).
#include <string>
#include "Globals.h"

namespace {
std::wstring ClassKey() {
    wchar_t text[64] = {};
    StringFromGUID2(CLSID_HarfiTextService, text, 64);
    return std::wstring(L"Software\\Classes\\CLSID\\") + text;
}

bool SetValue(HKEY key, const wchar_t *name, const std::wstring &value) {
    return RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE *>(value.c_str()),
                          static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) == ERROR_SUCCESS;
}

bool RegisterComClass() {
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(g_module, path, MAX_PATH);
    HKEY key = nullptr;
    std::wstring classKey = ClassKey();
    if (RegCreateKeyExW(HKEY_CURRENT_USER, classKey.c_str(), 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) !=
        ERROR_SUCCESS) return false;
    bool ok = SetValue(key, nullptr, L"Harfi");
    RegCloseKey(key);
    if (RegCreateKeyExW(HKEY_CURRENT_USER, (classKey + L"\\InprocServer32").c_str(), 0, nullptr, 0, KEY_WRITE,
                        nullptr, &key, nullptr) != ERROR_SUCCESS) return false;
    ok = ok && SetValue(key, nullptr, path) && SetValue(key, L"ThreadingModel", L"Apartment");
    RegCloseKey(key);
    return ok;
}

const GUID *const Categories[] = {&GUID_TFCAT_TIP_KEYBOARD, &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
                                  &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT};

bool RegisterProfile() {
    ITfInputProcessorProfileMgr *profiles = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&profiles)))) return false;
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(g_module, path, MAX_PATH);
    const wchar_t name[] = L"Harfi";
    HRESULT result = profiles->RegisterProfile(CLSID_HarfiTextService, HarfiLanguage, GUID_HarfiProfile, name,
                                               static_cast<ULONG>(wcslen(name)), path, static_cast<ULONG>(wcslen(path)),
                                               0, nullptr, 0, TRUE, 0);
    profiles->Release();
    return SUCCEEDED(result);
}

bool RegisterCategories(bool add) {
    ITfCategoryMgr *categories = nullptr;
    if (FAILED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr,
                                reinterpret_cast<void **>(&categories)))) return false;
    bool ok = true;
    for (const GUID *category : Categories) {
        HRESULT result = add ? categories->RegisterCategory(CLSID_HarfiTextService, *category, CLSID_HarfiTextService)
                             : categories->UnregisterCategory(CLSID_HarfiTextService, *category, CLSID_HarfiTextService);
        ok = ok && SUCCEEDED(result);
    }
    categories->Release();
    return ok;
}
}  // namespace

STDAPI DllRegisterServer() {
    if (!RegisterComClass() || !RegisterProfile() || !RegisterCategories(true)) return E_FAIL;
    return S_OK;
}

STDAPI DllUnregisterServer() {
    RegisterCategories(false);
    ITfInputProcessorProfileMgr *profiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&profiles)))) {
        profiles->UnregisterProfile(CLSID_HarfiTextService, HarfiLanguage, GUID_HarfiProfile, 0);
        profiles->Release();
    }
    RegDeleteTreeW(HKEY_CURRENT_USER, ClassKey().c_str());
    return S_OK;
}

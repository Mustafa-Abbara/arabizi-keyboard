#include "DisplayAttribute.h"
#include <new>

InputAttribute::InputAttribute() { ++g_objects; }
InputAttribute::~InputAttribute() { --g_objects; }

STDMETHODIMP InputAttribute::QueryInterface(REFIID riid, void **object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (riid == IID_IUnknown || riid == IID_ITfDisplayAttributeInfo) *object = static_cast<ITfDisplayAttributeInfo *>(this);
    if (!*object) return E_NOINTERFACE;
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) InputAttribute::AddRef() { return static_cast<ULONG>(++references_); }

STDMETHODIMP_(ULONG) InputAttribute::Release() {
    long left = --references_;
    if (left == 0) delete this;
    return static_cast<ULONG>(left);
}

STDMETHODIMP InputAttribute::GetGUID(GUID *guid) {
    if (!guid) return E_INVALIDARG;
    *guid = GUID_HarfiInput;
    return S_OK;
}

STDMETHODIMP InputAttribute::GetDescription(BSTR *description) {
    if (!description) return E_INVALIDARG;
    *description = SysAllocString(L"Harfi: text being typed");
    return *description ? S_OK : E_OUTOFMEMORY;
}

// A solid underline in the text's own colour; the text and its background stay as the app draws them.
STDMETHODIMP InputAttribute::GetAttributeInfo(TF_DISPLAYATTRIBUTE *attribute) {
    if (!attribute) return E_INVALIDARG;
    *attribute = {};
    attribute->crText.type = TF_CT_NONE;
    attribute->crBk.type = TF_CT_NONE;
    attribute->lsStyle = TF_LS_SOLID;
    attribute->fBoldLine = FALSE;
    attribute->crLine.type = TF_CT_NONE;
    attribute->bAttr = TF_ATTR_INPUT;
    return S_OK;
}

STDMETHODIMP InputAttribute::SetAttributeInfo(const TF_DISPLAYATTRIBUTE *) { return E_NOTIMPL; }

STDMETHODIMP InputAttribute::Reset() { return S_OK; }

EnumDisplayAttributes::EnumDisplayAttributes(ULONG next) : next_(next) { ++g_objects; }
EnumDisplayAttributes::~EnumDisplayAttributes() { --g_objects; }

STDMETHODIMP EnumDisplayAttributes::QueryInterface(REFIID riid, void **object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (riid == IID_IUnknown || riid == IID_IEnumTfDisplayAttributeInfo) {
        *object = static_cast<IEnumTfDisplayAttributeInfo *>(this);
    }
    if (!*object) return E_NOINTERFACE;
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) EnumDisplayAttributes::AddRef() { return static_cast<ULONG>(++references_); }

STDMETHODIMP_(ULONG) EnumDisplayAttributes::Release() {
    long left = --references_;
    if (left == 0) delete this;
    return static_cast<ULONG>(left);
}

STDMETHODIMP EnumDisplayAttributes::Clone(IEnumTfDisplayAttributeInfo **copy) {
    if (!copy) return E_INVALIDARG;
    *copy = new (std::nothrow) EnumDisplayAttributes(next_);
    return *copy ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP EnumDisplayAttributes::Next(ULONG count, ITfDisplayAttributeInfo **infos, ULONG *fetched) {
    if (!infos || (count > 1 && !fetched)) return E_INVALIDARG;
    ULONG done = 0;
    while (done < count && next_ < 1) {
        infos[done] = new (std::nothrow) InputAttribute();
        if (!infos[done]) break;
        ++done;
        ++next_;
    }
    if (fetched) *fetched = done;
    return done == count ? S_OK : S_FALSE;
}

STDMETHODIMP EnumDisplayAttributes::Reset() {
    next_ = 0;
    return S_OK;
}

STDMETHODIMP EnumDisplayAttributes::Skip(ULONG count) {
    bool enough = next_ + count <= 1;
    next_ = enough ? next_ + count : 1;
    return enough ? S_OK : S_FALSE;
}

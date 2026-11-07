// The look of the text being typed: underlined, as on the Mac. Apps ask the text service for it through
// ITfDisplayAttributeProvider; without it many draw the Latin text with no mark at all.
#pragma once
#include "Globals.h"

class InputAttribute : public ITfDisplayAttributeInfo {
public:
    InputAttribute();
    virtual ~InputAttribute();
    STDMETHODIMP QueryInterface(REFIID riid, void **object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;
    STDMETHODIMP GetGUID(GUID *guid) override;
    STDMETHODIMP GetDescription(BSTR *description) override;
    STDMETHODIMP GetAttributeInfo(TF_DISPLAYATTRIBUTE *attribute) override;
    STDMETHODIMP SetAttributeInfo(const TF_DISPLAYATTRIBUTE *attribute) override;
    STDMETHODIMP Reset() override;

private:
    std::atomic<long> references_{1};
};

// The one attribute above, for apps that list them all.
class EnumDisplayAttributes : public IEnumTfDisplayAttributeInfo {
public:
    explicit EnumDisplayAttributes(ULONG next = 0);
    virtual ~EnumDisplayAttributes();
    STDMETHODIMP QueryInterface(REFIID riid, void **object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;
    STDMETHODIMP Clone(IEnumTfDisplayAttributeInfo **copy) override;
    STDMETHODIMP Next(ULONG count, ITfDisplayAttributeInfo **infos, ULONG *fetched) override;
    STDMETHODIMP Reset() override;
    STDMETHODIMP Skip(ULONG count) override;

private:
    std::atomic<long> references_{1};
    ULONG next_;
};

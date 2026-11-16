// Harfi's own icon in the taskbar's input indicator, next to the language (ع), while Harfi is the keyboard: an "input
// mode" button, as Windows shows for the Japanese and Chinese keyboards. A click opens the Harfi window.
#pragma once
#include "Globals.h"

class LangBarButton : public ITfLangBarItemButton, public ITfSource {
public:
    LangBarButton();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void **object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;
    // ITfLangBarItem
    STDMETHODIMP GetInfo(TF_LANGBARITEMINFO *info) override;
    STDMETHODIMP GetStatus(DWORD *status) override;
    STDMETHODIMP Show(BOOL) override { return E_NOTIMPL; }
    STDMETHODIMP GetTooltipString(BSTR *tooltip) override;
    // ITfLangBarItemButton
    STDMETHODIMP OnClick(TfLBIClick click, POINT, const RECT *) override;
    STDMETHODIMP InitMenu(ITfMenu *) override { return E_NOTIMPL; }
    STDMETHODIMP OnMenuSelect(UINT) override { return E_NOTIMPL; }
    STDMETHODIMP GetIcon(HICON *icon) override;
    STDMETHODIMP GetText(BSTR *text) override;
    // ITfSource
    STDMETHODIMP AdviseSink(REFIID riid, IUnknown *sink, DWORD *cookie) override;
    STDMETHODIMP UnadviseSink(DWORD cookie) override;

private:
    ~LangBarButton();
    long references_ = 1;
    ITfLangBarItemSink *sink_ = nullptr;
};

// Adds the button to the thread's language bar (Activate) or takes it away (Deactivate). Either may fail silently:
// the keyboard works without it, Windows then shows only the language.
LangBarButton *AddLangBarButton(ITfThreadMgr *threadMgr);
void RemoveLangBarButton(ITfThreadMgr *threadMgr, LangBarButton *button);

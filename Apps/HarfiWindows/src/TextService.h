// The Harfi text input processor: receives keys in every app, asks the shared composer what they mean, and shows
// the result as composition (underlined) text or inserts it, like the Mac keyboard (ArabiziInputController).
#pragma once
#include <memory>
#include "ChipWindow.h"
#include "Core.h"
#include "Globals.h"

class TextService : public ITfTextInputProcessorEx, public ITfKeyEventSink, public ITfCompositionSink {
public:
    TextService();
    virtual ~TextService();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void **object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfTextInputProcessor(Ex)
    STDMETHODIMP Activate(ITfThreadMgr *threadMgr, TfClientId clientId) override;
    STDMETHODIMP ActivateEx(ITfThreadMgr *threadMgr, TfClientId clientId, DWORD flags) override;
    STDMETHODIMP Deactivate() override;

    // ITfKeyEventSink
    STDMETHODIMP OnSetFocus(BOOL foreground) override;
    STDMETHODIMP OnTestKeyDown(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) override;
    STDMETHODIMP OnKeyDown(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) override;
    STDMETHODIMP OnKeyUp(ITfContext *context, WPARAM wParam, LPARAM lParam, BOOL *eaten) override;
    STDMETHODIMP OnPreservedKey(ITfContext *context, REFGUID guid, BOOL *eaten) override;

    // ITfCompositionSink: the app ended the composition (focus moved, clicked elsewhere).
    STDMETHODIMP OnCompositionTerminated(TfEditCookie cookie, ITfComposition *composition) override;

private:
    // The composer's effect for this key, computed once in OnTestKeyDown and carried out in OnKeyDown.
    bool Decide(WPARAM wParam, LPARAM lParam);
    // Carries out an effect in the app: synchronously during a key press, asynchronously after a chip click.
    void Apply(ITfContext *context, const Effect &effect, bool duringKey = true);
    // The chip row for this effect above the composition, or hidden.
    void UpdateChips(ITfContext *context, TfEditCookie cookie, const Effect &effect);
    void SetComposition(ITfContext *context, TfEditCookie cookie, const std::wstring &text);
    void Commit(ITfContext *context, TfEditCookie cookie, const std::wstring &text);
    // Sends the key again after its text was inserted, so the app gets it (commitAndPass).
    static void Resend(WPARAM wParam, LPARAM lParam);

    std::atomic<long> references_{1};
    ITfThreadMgr *threadMgr_ = nullptr;
    TfClientId clientId_ = TF_CLIENTID_NULL;
    ITfComposition *composition_ = nullptr;
    std::unique_ptr<Core> core_;
    ChipWindow chips_;
    ITfContext *context_ = nullptr;  // where the last key was typed: chip clicks act there
    bool decided_ = false;
    WPARAM decidedKey_ = 0;
    Effect decision_;
};

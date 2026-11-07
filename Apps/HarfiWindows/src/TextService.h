// The Harfi text input processor: receives keys in every app, asks the shared composer what they mean, and shows
// the result as composition (underlined) text or inserts it, like the Mac keyboard (ArabiziInputController).
#pragma once
#include <memory>
#include "ChipWindow.h"
#include "Core.h"
#include "Globals.h"
#include "PreviewWindow.h"

class TextService : public ITfTextInputProcessorEx,
                    public ITfKeyEventSink,
                    public ITfCompositionSink,
                    public ITfDisplayAttributeProvider {
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

    // ITfDisplayAttributeProvider: how apps draw the text being typed (DisplayAttribute.h).
    STDMETHODIMP EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo **attributes) override;
    STDMETHODIMP GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo **info) override;

private:
    // What the composer needs to know about the text field before a key (its Context).
    struct Field {
        bool secure = false;            // a password or PIN field
        bool atLastConversion = false;  // the cursor is right after the text Harfi last inserted
        std::wstring selected;          // the selected text, read only for Alt+Enter
    };

    // The composer's effect for this key, computed once in OnTestKeyDown and carried out in OnKeyDown.
    bool Decide(ITfContext *context, WPARAM wParam, LPARAM lParam);
    Field ReadField(ITfContext *context, bool wantSelection);
    // Typing moved to `context`: what the composer remembers belongs to the old field, so it starts over.
    void Follow(ITfContext *context);
    // Ends the composition left in context_ (the Latin stays as typed) and empties the composer.
    void Forget(bool sync);
    // Carries out an effect in the app: synchronously during a key press, asynchronously after a chip click.
    // `key`: the key's JSON (empty for a click), for the hints.
    void Apply(ITfContext *context, const Effect &effect, const std::string &key = {}, bool duringKey = true);
    // The preview box, the chip row and the hints after an effect, as the Mac keyboard shows them.
    void UpdateBoxes(ITfContext *context, TfEditCookie cookie, const Effect &effect, const std::string &key);
    // The live preview for the Latin being typed (`whole` after a pause), or hidden when nothing shows yet.
    void ShowPreview(ITfContext *context, TfEditCookie cookie, bool whole);
    // Shows the preview again after `milliseconds` (a pause in typing, or the model's conversion coming).
    void RefreshPreviewAfter(UINT milliseconds, bool whole);
    // The screen rectangle of the text being typed (or of the cursor): from the app, else the caret, else the last
    // good one, else the mouse.
    RECT TextRect(ITfContext *context, TfEditCookie cookie);
    void SetComposition(ITfContext *context, TfEditCookie cookie, const std::wstring &text, int replacingLength);
    void Commit(ITfContext *context, TfEditCookie cookie, const std::wstring &text);
    // Marks `range` as text being typed (underlined), or clears the mark.
    void Underline(ITfContext *context, TfEditCookie cookie, ITfRange *range, bool on);
    // Sends the key again after its text was inserted, so the app gets it (commitAndPass).
    static void Resend(WPARAM wParam, LPARAM lParam);

    std::atomic<long> references_{1};
    ITfThreadMgr *threadMgr_ = nullptr;
    TfClientId clientId_ = TF_CLIENTID_NULL;
    TfGuidAtom inputAtom_ = TF_INVALID_GUIDATOM;  // GUID_HarfiInput, as the attribute property's value
    ITfComposition *composition_ = nullptr;
    ITfRange *lastCommitEnd_ = nullptr;  // where the last inserted text ends, for Ctrl+Z and Alt+Tab
    std::unique_ptr<Core> core_;
    ChipWindow chips_;
    PreviewWindow preview_;
    RECT lastRect_ = {};
    bool hasLastRect_ = false;
    ITfContext *context_ = nullptr;  // where the last key was typed: chip clicks act there
    bool decided_ = false;
    WPARAM decidedKey_ = 0;
    std::string decidedJson_;  // the key as sent to the composer, without the field's context
    bool wasComposing_ = false;  // Latin was being typed before the key (for the ↑ hint)
    bool loggedKey_ = false;     // DebugLog: the first key of this activation was logged
    // The habit the tip on screen announces (ADR 0033): Esc before `habitUntil_` refuses it.
    std::string habitLatin_, habitSpelling_;
    ULONGLONG habitUntil_ = 0;
    Effect decision_;
};

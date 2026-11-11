Harfi turns Lebanese Arabizi into Arabic as you type, entirely on your own computer.

**New in 0.3.0**

- **Fixing a word is quicker:** ↑ now opens on the word Harfi is least sure of, and its list of spellings is wider and better ordered: for a word Harfi got wrong, the right spelling is first about half the time (it was under a third) and in the list nearly four times out of five (it was half). The sentence as you typed it shows above the list.
- **Harfi learns your spellings on the Mac too:** pick the same spelling for a word three times on two different days and Harfi writes it your way from then on. It tells you when that happens, and you can say no.
- **Faster on Windows:** the preview and Enter are about twice as fast while you type. This is the new "Faster preview" setting, on by default; now and then it makes a word come out differently, and it can be switched off in the Harfi window (the Mac has the same switch in its settings).
- **A Harfi window on Windows:** "Harfi" in the Start menu has the settings, the words you taught it (stop a habit, forget a word), the keys, and a first-steps page.
- **An installer you double-click on Windows:** `Install Harfi.exe` instead of a PowerShell script, with the download's progress. Harfi also shows in Windows' installed apps, where it can be removed.
- **Mixed Arabic and English keep their order** after Enter in apps such as Notepad and WhatsApp, and an English preview reads left to right.

The model is unchanged (v3): if you have it, it is not downloaded again.

**Mac** (Apple silicon Mac, macOS 14 or later, no admin password):

```bash
curl -fsSL https://raw.githubusercontent.com/Mustafa-Abbara/arabizi-keyboard/main/scripts/install_harfi.sh | bash
```

Then turn it on once in System Settings → Keyboard → Input Sources → Edit… → + → Arabic → Harfi. The full guide is [docs/INSTALL.md](https://github.com/Mustafa-Abbara/arabizi-keyboard/blob/main/docs/INSTALL.md).

The installer downloads the conversion model (808 MB) from the `model-v3` release and resumes if the connection drops. Built with Llama: the model is a fine-tune of Llama 3.2 1B Instruct, under the Llama 3.2 Community License.

**Windows** (64-bit Windows 10 or 11, preview): download `Harfi-Windows-x64.zip` below, right-click it → Extract All, then double-click `Install Harfi.exe` and press Install (Windows may say it does not know the publisher: More info → Run anyway). Turn it on once in Settings → Time & language → Language & region → Arabic (Lebanon) → Language options → Add a keyboard → Harfi, and switch with Win+Space. The full guide is [Apps/HarfiWindows/README.md](https://github.com/Mustafa-Abbara/arabizi-keyboard/blob/main/Apps/HarfiWindows/README.md).

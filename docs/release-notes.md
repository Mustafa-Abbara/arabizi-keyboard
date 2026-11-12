Harfi turns Lebanese Arabizi into Arabic as you type, entirely on your own computer.

**New in 0.3.1**

- **Installing is quicker:** you can type with Harfi within a minute, while its model downloads in the background. Until the model arrives Harfi uses its rules, which are less accurate, and its window shows how far the download has got.
- **No more digging in Settings:** on the Mac, macOS asks you to allow Harfi once (click Allow); on Windows, the installer adds Harfi to your keyboards under Arabic (Lebanon) by itself.
- **One file on Windows:** download `Harfi-Setup.exe` and double-click it. The zip is still there for anyone who prefers it.
- **Updating says so:** running the Mac installer again ends with "Harfi is updated", and on Windows the model parts already downloaded are kept.
- **Fixes:** two apps saving a fix at the same moment now keep both; on the Mac the engine frees its memory after 30 idle minutes as intended, and the preview leaves room for the list of spellings.

The model is unchanged (v3): if you have it, it is not downloaded again.

**Mac** (Apple silicon Mac, macOS 14 or later, no admin password):

```bash
curl -fsSL https://raw.githubusercontent.com/Mustafa-Abbara/arabizi-keyboard/main/scripts/install_harfi.sh | bash
```

macOS asks you to allow Harfi once: click Allow, then switch to it with Ctrl+Space. The full guide is [docs/INSTALL.md](https://github.com/Mustafa-Abbara/arabizi-keyboard/blob/main/docs/INSTALL.md).

The installer then downloads the conversion model (808 MB) from the `model-v3` release while you type, and resumes if the connection drops. Built with Llama: the model is a fine-tune of Llama 3.2 1B Instruct, under the Llama 3.2 Community License.

**Windows** (64-bit Windows 10 or 11, preview): download `Harfi-Setup.exe` below and double-click it (Windows may say it does not know the publisher: More info → Run anyway; if it asks for administrator rights, allow it once). It adds Harfi to your keyboards: switch with Win+Space. The full guide is [Apps/HarfiWindows/README.md](https://github.com/Mustafa-Abbara/arabizi-keyboard/blob/main/Apps/HarfiWindows/README.md).

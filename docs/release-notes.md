Harfi turns Lebanese Arabizi into Arabic as you type, entirely on your own computer.

**Mac** (Apple silicon Mac, macOS 14 or later, no admin password):

```bash
curl -fsSL https://raw.githubusercontent.com/Mustafa-Abbara/arabizi-keyboard/main/scripts/install_harfi.sh | bash
```

Then turn it on once in System Settings → Keyboard → Input Sources → Edit… → + → Arabic → Harfi. The full guide is [docs/INSTALL.md](https://github.com/Mustafa-Abbara/arabizi-keyboard/blob/main/docs/INSTALL.md).

The installer downloads the conversion model (808 MB) from the `model-v3` release and resumes if the connection drops. Built with Llama: the model is a fine-tune of Llama 3.2 1B Instruct, under the Llama 3.2 Community License.

**Windows** (64-bit Windows 10 or 11, preview): download `Harfi-Windows-x64.zip` below, right-click it → Extract All, then right-click `install.ps1` → Run with PowerShell. Turn it on once in Settings → Time & language → Language & region → Arabic (Lebanon) → Language options → Add a keyboard → Harfi, and switch with Win+Space. The full guide is [Apps/HarfiWindows/README.md](https://github.com/Mustafa-Abbara/arabizi-keyboard/blob/main/Apps/HarfiWindows/README.md).

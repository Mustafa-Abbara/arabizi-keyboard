# Installing Harfi

Harfi turns Lebanese Arabizi (`kifak, shu 3am ta3mel?`) into Arabic (كيفك، شو عم تعمل؟) as you type, in any app. Everything happens on your Mac: nothing you type is sent anywhere.

**You need:** a Mac with Apple silicon (M1 or later) and macOS 14 (Sonoma) or later, about 1 GB of free space, and an internet connection for the first install. No admin password.

## 1. Install

Open **Terminal** (press ⌘Space, type Terminal, press Enter), paste this line and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/Mustafa-Abbara/arabizi-keyboard/main/scripts/install_harfi.sh | bash
```

It installs Harfi and downloads its model (808 MB). If your connection drops, it carries on where it stopped; if you close Terminal, run the same line again and it resumes.

## 2. Turn it on (once)

1. Open **System Settings → Keyboard**, and under **Text Input** click **Edit…** next to Input Sources.
2. Click **+**, choose **Arabic**, select **Harfi**, and click **Add**.
3. If Harfi is not in the list, log out and back in once, then try again.

## 3. Use it

1. Switch to Harfi with **Ctrl+Space** (or the input menu in the menu bar).
2. Type in Arabizi. A small box above your text shows the Arabic as you go.
3. Press **Enter**: your text becomes Arabic. Press **Enter** again to send.

| To | Press |
|---|---|
| Fix a word before converting | **↑**, then ← → to choose the word and a number to pick its spelling |
| Fix a word right after converting | **⌥Tab** |
| Get your Latin text back | **⌘Z** right after converting |
| Keep the text as typed | **Esc** |

A word with a dashed line under it is probably wrong: **↑** starts on it.

The **Harfi** items in the input menu open the settings, the words Harfi has learned from your fixes, and this help.

## Updating

Run the install line again. The model is not downloaded again unless it changed.

## Removing

```bash
curl -fsSL https://raw.githubusercontent.com/Mustafa-Abbara/arabizi-keyboard/main/scripts/install_harfi.sh | bash -s -- --uninstall
```

Then remove Harfi from Input Sources (**−**). The words you taught it stay on your Mac until you choose **Forget all my words** in Harfi's window before removing it.

## Questions

**Is it safe?** Harfi converts on your Mac with a model that runs in a sandbox with no network access. It keeps only the single words you correct, encrypted, for 30 days, so your spelling comes first next time. Password fields are never touched.

**Why Terminal?** Harfi is a free project and is not signed with a paid Apple Developer ID, so macOS would block a normal download (and a Homebrew install). The install line downloads and signs it on your own Mac instead, which macOS accepts.

**Something does not work.** Switch to another keyboard with Ctrl+Space and back. If typing feels stuck, choose another input source from the menu bar. Open an issue on [GitHub](https://github.com/Mustafa-Abbara/arabizi-keyboard/issues) with what you typed and what you saw.

---

Built with Llama: the conversion model is a fine-tune of Llama 3.2 1B Instruct, licensed under the Llama 3.2 Community License (see [NOTICE](../NOTICE)).

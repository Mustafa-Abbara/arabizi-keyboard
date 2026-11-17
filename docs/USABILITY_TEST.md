# Usability test: script and results sheet

How a person who has never seen Harfi installs it and uses it, on their own computer, with an observer watching. One
session takes about 40 minutes.

> **Before any outside participant (A8, ADR 0001):** the study needs AUB IRB approval first (student exemption, a
> faculty PI, CITI training) and a signed consent form from each participant. Until then, run it only as a dry run
> with team members, to fix the script.

## Who

- **6 to 9 people** who text in Arabizi. At least **2 aged 55 or more**, at least **2 who have never added a keyboard**
  to their computer, and both systems: **3 or more on a Mac** (Apple silicon, macOS 14+) and **3 or more on Windows**
  (10 or 11, 64-bit).
- Not the team, and not anyone who has seen Harfi used.
- Their own computer, with Harfi not installed (on a Mac, check Input Sources; on Windows, Settings → Language &
  region). If that isn't possible, a computer they use often, signed in to a new user account.

## What the observer needs

- This script printed, and one results sheet per participant (below).
- A stopwatch, and a good internet connection (the model is 808 MB; note the speed).
- The three sentences for task 5, prepared before the session (see task 5).
- No screen recording and no copies of anything the participant types for themselves. Note what they *did*, not what
  they wrote. The tasks use the sentences given here.

## Help policy

Give help only when the participant is stuck for **2 minutes** or asks, and in this order. Note the level on the
sheet:

1. "What are you looking for?" (no information)
2. A hint that points to the place: "Look at the bottom of the page", "Look at the top of the screen".
3. Say exactly what to do. The task then counts as **failed**, and you move on.

Never touch their keyboard or mouse.

## Introduction (read aloud)

> Thanks for helping. We made a keyboard called Harfi that turns Arabizi into Arabic as you type. We're testing the
> keyboard, not you: if something is hard, that's our mistake, and it's what we want to find.
>
> I'll give you some tasks. Please think out loud as you go: say what you're looking at, what you expect and what
> surprises you. I can't help much, because we want to see what happens when you're on your own, but you can stop at
> any time, for any reason.
>
> I'll take notes about what you do, not about what you write. Is that OK?

Note the participant's age group, system and version, and whether they have added a keyboard before.

## Tasks

Read each task aloud as written, then start the stopwatch. Stop it when the success criterion is met or after the time
limit.

### 1. Install Harfi (limit 15 minutes, model download excluded)

> "A friend told you about Harfi. Here's its website: harfi on github pages. Install it so you can use it."

Open `https://mustafa-abbara.github.io/arabizi-keyboard/` in their browser for them; nothing else.

- **Success:** Harfi is selected as the keyboard and converts a word, in any app.
- **Watch for:** which button they press; on the Mac, how they react to Terminal and to pasting a command, and
  whether they see and click **Allow**; on Windows, the "unknown publisher" warning (More info → Run anyway) and the
  administrator prompt; whether they find **Ctrl Space** / **Win Space**; whether they wait for the model or start
  typing.
- Note separately how long the model took to download, and whether they noticed the download in Harfi's window.

### 2. Check it works (limit 3 minutes)

> "The website has a way to check that Harfi works. Try it."

- **Success:** the "Check it works" box turns green.
- **Watch for:** whether they find the box; whether the Latin message helps if Harfi wasn't selected.

### 3. Write a message (limit 3 minutes)

> "In Notes (Mac) or Notepad (Windows), write: **kifak, shu 3am ta3mel?** and make it Arabic."

- **Success:** the line is in Arabic.
- **Watch for:** whether they press Enter to convert; whether the live preview above the text helps or distracts;
  whether a second Enter surprises them.

### 4. Write in a chat app (limit 4 minutes)

> "Now send the same kind of message in WhatsApp (or the chat app you use) to yourself: **ana ra7 ballesh bokra
> 3al 8**."

Use "message yourself" or a test chat; never a real conversation.

- **Success:** the message is sent in Arabic.
- **Watch for:** Enter to convert, Enter again to send; whether they expect one Enter to do both.

### 5. Fix a word (limit 5 minutes)

Before the session, pick three sentences from the **dev set** (never the test set) that the current model converts
with one word wrong, and write them on cards with the right Arabic word. Give one card.

> "Type this sentence and convert it. One word will come out differently from what you want: change it to the
> spelling on the card."

- **Success:** the word matches the card, with ↑ (before or right after Enter) or by retyping.
- **Watch for:** whether they find **↑** without help (the tip after a conversion says "↑ to fix a word"); whether
  they choose the word with ← →; whether they pick with a number or a click. Note if they retyped instead.

### 6. Get the Latin back (limit 3 minutes)

> "Write **yalla bye** and convert it. Now you'd like to keep it in Latin letters instead. Get the Latin back."

- **Success:** "yalla bye" in Latin.
- **Watch for:** ⌘Z (Mac) / Ctrl Z (Windows) right after converting, Esc before converting (Windows), or deleting and
  typing again.

### 7. English in the middle (limit 3 minutes)

> "Write: **3ende meeting bokra at 10** and convert it."

- **Success:** the Arabizi words are Arabic and "meeting", "at" and "10" stay as they were.
- **Watch for:** whether the result reads in the right order to them.

### 8. Change a setting (limit 4 minutes)

> "You'd rather not see the Arabic preview while you type. Turn it off."

- **Success:** the live preview is off.
- **Watch for:** where they look first (menu bar or Start menu, the Harfi window, system settings).

### 9. Go back to your usual keyboard (limit 2 minutes)

> "Now go back to your usual keyboard and write **hello** in English."

- **Success:** "hello" typed with their usual keyboard.

## After the tasks

### SUS questionnaire

The System Usability Scale (Brooke, 1986), read or handed out after the tasks. Each item from 1 (strongly disagree) to 5
(strongly agree). An Arabic version is offered only after a native speaker has checked the translation.

1. I think that I would like to use Harfi frequently.
2. I found Harfi unnecessarily complex.
3. I thought Harfi was easy to use.
4. I think that I would need the support of a technical person to be able to use Harfi.
5. I found the various functions in Harfi were well integrated.
6. I thought there was too much inconsistency in Harfi.
7. I would imagine that most people would learn to use Harfi very quickly.
8. I found Harfi very cumbersome to use.
9. I felt very confident using Harfi.
10. I needed to learn a lot of things before I could get going with Harfi.

**Score:** for odd items, the answer minus 1; for even items, 5 minus the answer; add them and multiply by 2.5 (0 to
100). Above 68 is about average; above 80 is good.

### Questions (note the answers in a few words)

1. What was the hardest part?
2. Was anything different from what you expected?
3. Would you keep it installed? Why or why not?
4. Who do you know who would use it, and who wouldn't?

Then thank them, and offer to remove Harfi with them (website → "How do I remove it?") or leave it installed.

## Results sheet (one per participant)

| Field | Value |
|---|---|
| Participant | P1, P2, … (no names) |
| Age group | under 30 / 30–54 / 55+ |
| System and version | e.g. macOS 26.6, Windows 11 23H2 |
| Added a keyboard before? | yes / no |
| Connection speed, model download time | |

| Task | Done? (yes / with help / failed) | Help level (0–3) | Time | What happened |
|---|---|---|---|---|
| 1 Install | | | | |
| 2 Check it works | | | | |
| 3 Write a message | | | | |
| 4 Chat app | | | | |
| 5 Fix a word | | | | |
| 6 Latin back | | | | |
| 7 English in the middle | | | | |
| 8 Change a setting | | | | |
| 9 Usual keyboard | | | | |

SUS answers (1–10), SUS score, and the four answers.

Keep filled sheets in `eval/results/private/usability/` (not committed). What is published is the summary only: per
task, how many succeeded, the median time and the help levels; the SUS mean and range; and the problems seen, each
with how many participants hit it. No quotes that could identify anyone.

## After all sessions

- List each problem with its count and the task it blocked, worst first.
- Each problem seen by two or more participants gets an issue.
- Compare the 55+ group with the others on task 1 and task 5, the two most likely to differ.

# RUN ALL, round 5 (machine A)

You are working in this folder on the user's computer. Your job is to produce 1,800 training pairs (Lebanese Arabizi → Lebanese Arabic script) by working through the six task files in `chats5/`, one after another, saving everything in `output/`. The person who started you is only helping; they don't know the details. **Do not ask them anything. Work until all six are done.** If you need permission to write files, ask for it once.

This round is aimed at what the current model (v4) still gets wrong on real typing: long, messy chat messages; common words whose meaning depends on the sentence; ط ص ض ظ typed as plain t s d z; English and French words that must stay Latin; and rare words or new word forms.

## The folder

```
RUN_ALL_5.md                   this file
chats5/chat_1.md … chat_6.md   the six tasks, each 6 rounds of 50 pairs
reference/known_words.tsv      every Arabic word the model has trained on, with counts (tab-separated)
reference/known_arabizi.tsv    every Arabizi spelling the model has trained on, with counts
output/                        where you save your work (create it if missing)
```

## Comparing words

When this file or a task says a word is "in" or "not in" a reference file, compare without diacritics or tatweel, and treat أ / إ / آ / ا, final ى / ي and final ة / ه as the same in Arabic; compare Arabizi in lowercase. Use code to look words up, not memory.

## The loop

For N = 1 to 6:

1. **Skip what's done.** If `output/A5_chat_N.jsonl` already has 300 valid lines, go to the next N. If it has fewer, this chat was interrupted: continue it from the id after the last valid line.
2. **Read what exists.** Read every `output/A5_chat_*.jsonl` written so far. Don't write a pair close to any earlier pair, and for rounds of kind "new" don't reuse an earlier pair's rare word.
3. **Read the task.** Read `chats5/chat_N.md` completely and follow it exactly: its rules, the real-chat style, the spelling guide, examples, rounds and self-check.
4. **Work round by round.** For each round:
   - write the round's 50 pairs and check them as the task file says;
   - **check the real-chat style with code**, and rewrite pairs until the round passes:
     - every Arabizi message has 8 to 30 words, and the round's average is at least 10;
     - between 7 and 15 of the 50 messages contain emoji;
     - no Arabizi word contains the digit 6 or 9;
     - at most 2 of the 50 messages end with `.` `?` or `!`;
     - at least 3% of the round's Arabizi words (of 3+ letters) have no vowel (a, e, i, o, u);
     - no accented Latin letter (é, è, à, ç...) in the Arabizi;
   - **check the round's own rule with code**, and replace any pair that fails it:
     - kind **new**: each rare word is not in `known_words.tsv`, and isn't one of its words with only a prefix added (و، ف، ب، ل، ع، ك، ال، بال، وال، لل، عال);
     - kind **inflect**: each rare word (the new form) is not in `known_words.tsv`;
     - kind **low**: the rare words come from the round's list;
     - kind **heavy**: each rare word comes from the round's list, and the Arabizi word typed for it uses no digit 6 or 9;
     - kind **latin**: each rare word is a Latin word that appears exactly, as typed, in both the Arabizi and the Arabic, and each pair has at least two;
     - kind **context**: each pair has at least two of the round's short words;
   - **append** the 50 lines to `output/A5_chat_N.jsonl` (UTF-8, one JSON object per line, nothing else in the file);
   - check that every line parses as JSON and that the ids run in order with no gaps or repeats; fix the file if not;
   - update `output/A5_progress.txt` with one line: `chat_N round R done: <lines in file> lines`.
5. Go on to the next round, then the next chat, **without stopping to report or ask**.

If you run out of room in one turn, stop at the end of a round. When you are told to continue (or started again with this file), the loop above picks up exactly where you stopped.

## At the very end

When all six files have 300 valid lines, write `output/A5_DONE.txt` with:

- the number of lines in each file and in total, and per kind;
- the style numbers over all 1,800 pairs: average words per message, share with emoji, share ending in punctuation, share of vowelless words;
- how many pairs passed their round's rule check, per kind;
- a plain list of words you skipped or were unsure about, with no explanations.

Then tell the person: "All done. Send the `output` folder back."

## Never

- Never edit anything outside `output/`.
- Never print the pairs in the chat; they go in the files.
- Never write out your reasoning, drafts or explanations, in the chat or in any file. The only output is the pairs, plus the short status lines in the progress and DONE files.
- Never invent a word or a spelling to satisfy a rule. If you can't meet a round's rule with certain words, write fewer pairs of that kind, fill the round with ordinary long real-chat pairs, and note it in the DONE file.

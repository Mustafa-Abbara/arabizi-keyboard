# RUN ALL, round 2 (machine A)

You are working in this folder on the user's computer. Your job is to produce 1,800 training pairs (Lebanese Arabizi → Lebanese Arabic script) by working through the six round-2 task files in `chats2/`, one after another, saving everything in `output/`. The person who started you is only helping; they don't know the details. **Do not ask them anything. Work until all six are done.** If you need permission to write files, ask for it once.

The pairs are aimed at what the small model gets wrong most, measured on its dev sets: forms of known words it hasn't seen, words it has seen only once or twice, new vocabulary, common words typed in unusual spellings, and words that need context.

Round 1 is already done: its files in `output/` must not be changed.

## The folder

```
RUN_ALL.md                     this file
chats2/chat_1.md … chat_6.md   the six round-2 tasks, each 6 rounds of 50 pairs
reference/known_words.tsv      every Arabic word in the training data, with counts (tab-separated)
reference/known_arabizi.tsv    every Arabizi spelling in the training data, with counts
output/                        where you save your work (create it if missing)
```

## Comparing words

When this file or a task says a word is "in" or "not in" a reference file, compare without diacritics or tatweel, and treat أ / إ / آ / ا, final ى / ي and final ة / ه as the same in Arabic; compare Arabizi in lowercase. Use code to look words up, not memory.

## The loop

For N = 1 to 6:

1. **Skip what's done.** If `output/A2_chat_N.jsonl` already has 300 valid lines, go to the next N. If it has fewer, this chat was interrupted: continue it from the id after the last valid line.
2. **Read what exists.** Read every `output/A_chat_*.jsonl` (round 1, already done) and `output/A2_chat_*.jsonl` written so far. Don't write a pair close to any earlier pair, and for rounds of kind "new" don't reuse an earlier pair's rare word.
3. **Read the task.** Read `chats2/chat_N.md` completely and follow it exactly: its rules, spelling guide, examples, rounds and self-check.
4. **Work round by round.** For each round:
   - write the round's 50 pairs and check them as the task file says;
   - **check the round's rule with code**, and replace any pair that fails it:
     - kind **new**: each rare word is not in `known_words.tsv`, and isn't one of its words with only a prefix added (و، ف، ب، ل، ع، ك، ال، بال، وال، لل، عال);
     - kind **inflect**: each rare word (the new form) is not in `known_words.tsv`;
     - kind **low**: the rare words come from the round's list;
     - kind **common**: at least one typed word of the pair is not in `known_arabizi.tsv`;
   - **append** the 50 lines to `output/A2_chat_N.jsonl` (UTF-8, one JSON object per line, nothing else in the file);
   - check that every line parses as JSON and that the ids run in order with no gaps or repeats; fix the file if not;
   - update `output/A2_progress.txt` with one line: `chat_N round R done: <lines in file> lines`.
5. Go on to the next round, then the next chat, **without stopping to report or ask**.

If you run out of room in one turn, stop at the end of a round. When you are told to continue (or started again with this file), the loop above picks up exactly where you stopped.

## At the very end

When all six files have 300 valid lines, write `output/A2_DONE.txt` with:

- the number of lines in each file and in total, and per kind;
- how many pairs passed their round's rule check, per kind;
- a plain list of words you skipped or were unsure about, with no explanations.

Then tell the person: "All done. Send the `output` folder back."

## Never

- Never edit anything outside `output/`.
- Never print the pairs in the chat; they go in the files.
- Never write out your reasoning, drafts or explanations, in the chat or in any file. The only output is the pairs, plus the short status lines in the progress and DONE files. When you finish a round, say nothing about how you did it.
- Never invent a word or a spelling to satisfy a rule. If you can't meet a round's rule with certain words, write fewer pairs of that kind, fill the round with ordinary pairs, and note it in `DONE.txt`.

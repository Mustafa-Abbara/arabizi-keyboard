/* The C interface of the shared Harfi core (Packages/ArabiziCore/Sources/HarfiCoreC, ADR 0032).
   Every string is UTF-8; strings returned are owned by the caller and freed with harfi_free. */
#ifndef HARFI_CORE_H
#define HARFI_CORE_H
#ifdef __cplusplus
extern "C" {
#endif

typedef void *harfi_core;
typedef void *harfi_composer;

harfi_core harfi_core_open(const char *rules_dir);   /* NULL when the rule files cannot be read */
void harfi_core_close(harfi_core core);
char *harfi_convert(harfi_core core, const char *text);     /* the rules' Arabic; plain English unchanged */
int harfi_is_english(harfi_core core, const char *text);    /* 1 when plain English */
/* The live preview box for the Latin typed so far: {"arabic": [words], "latin": the Latin typed since, "doubtful":
   [word indices], "pending": the engine's conversion is coming (the rules' shown until then; ask again shortly)},
   or {} when nothing shows yet. whole (nonzero after a pause in typing): the last word too. */
char *harfi_preview(harfi_core core, const char *text, int whole);
/* The user said no to a habit the keyboard announced ("learnedLatin"/"learnedSpelling" in a reply): it is never
   applied or announced again (ADR 0033). */
void harfi_habit_refuse(harfi_core core, const char *latin, const char *spelling);

harfi_composer harfi_composer_new(harfi_core core);
void harfi_composer_free(harfi_composer composer);
/* key: {"key":"text","text":"a"} or {"key":"enter"|"backspace"|"escape"|"undo"|"convertSelection"|"suggest"|
   "arrowLeft"|"arrowRight"|"arrowUp"|"arrowDown"|"tab"|"backtab"|"other"}, optional "secureInput",
   "cursorAtLastConversion" (booleans), "selectedText". Returns {"effect": "pass"|"consume"|"update"|"commit"|
   "commitAndPass"|"replaceSelection"|"restore"|"suggest"|"commitAndCompose", "marked", "text", "selected",
   "replacingLength", "candidates", "choice", "word" (the word being fixed), "spelling", and while fixing before
   sending "fixingWords", "fixingIndex", "fixingDoubtful" (the preview around the chips), and once, when a pick has
   just made a typed word a habit, "learnedLatin" and "learnedSpelling" (ADR 0033), and after a conversion is sent
   with a word the model was unsure of, "unsureWord" (ADR 0034)}. */
char *harfi_composer_key(harfi_composer composer, const char *key_json);
/* A spelling (or, while spelling, a letter) clicked in the chip row: the same reply as harfi_composer_key. */
char *harfi_composer_pick(harfi_composer composer, const char *candidate);
char *harfi_composer_buffer(harfi_composer composer);
void harfi_free(char *text);

#ifdef __cplusplus
}
#endif
#endif

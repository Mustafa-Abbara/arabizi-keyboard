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

harfi_composer harfi_composer_new(harfi_core core);
void harfi_composer_free(harfi_composer composer);
/* key: {"key":"text","text":"a"} or {"key":"enter"|"backspace"|"escape"|"undo"|"convertSelection"|"suggest"|
   "arrowLeft"|"arrowRight"|"arrowUp"|"arrowDown"|"tab"|"backtab"|"other"}, optional "secureInput",
   "cursorAtLastConversion" (booleans), "selectedText". Returns {"effect": "pass"|"consume"|"update"|"commit"|
   "commitAndPass"|"replaceSelection"|"restore"|"suggest"|"commitAndCompose", "marked", "text", "selected",
   "replacingLength", "candidates", "choice"}. */
char *harfi_composer_key(harfi_composer composer, const char *key_json);
char *harfi_composer_buffer(harfi_composer composer);
void harfi_free(char *text);

#ifdef __cplusplus
}
#endif
#endif

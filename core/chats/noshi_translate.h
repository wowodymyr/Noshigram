#ifndef NOSHI_TRANSLATE_H
#define NOSHI_TRANSLATE_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_tl.h"

/* the translation Telegram does itself, one of the providers of the translator: messages.translateText on a piece
   of text */

#define NOSHI_TRANSLATE_TEXT_MAX 16384
#define NOSHI_TRANSLATE_LANG_MAX 16

/* the text, at most NOSHI_TRANSLATE_TEXT_MAX bytes and not empty, into the language code to_lang ("ru", "pt-br",
   "zh-CN"; letters, digits and dashes, 1 to NOSHI_TRANSLATE_LANG_MAX - 1 of them); anything else is
   NOSHI_E_ARG */
noshi_status noshi_translate_request(noshi_arena *arena, const char *text, const char *to_lang, noshi_tl_value **out);
/* a messages.translateResult: the first translated text, cut at a character boundary to cap - 1 bytes;
   NOSHI_E_MALFORMED for any other answer or one without a text; out is empty then */
noshi_status noshi_translate_parse(const noshi_tl_value *answer, char *out, size_t cap);

#endif

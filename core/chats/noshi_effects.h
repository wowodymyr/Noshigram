#ifndef NOSHI_EFFECTS_H
#define NOSHI_EFFECTS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_messages.h"
#include "noshi_tl.h"

/* the animated effects a message of a private chat can be sent with (messages.getAvailableEffects): the server names each by the emoji that stands for it */
#define NOSHI_EFFECTS_MAX 64
#define NOSHI_EFFECT_EMOTICON_MAX 32

typedef struct noshi_effect {
    int64_t id;
    char emoticon[NOSHI_EFFECT_EMOTICON_MAX];
    uint8_t premium;             /* the effect needs Telegram Premium */
    int64_t sticker_id;          /* the sticker that shows the effect in a list, 0 when it has none */
    int64_t animation_id;        /* the full screen animation, 0 when it has none */
    noshi_custom_emoji animation; /* the document of the animation, id 0 when the answer does not carry it */
    noshi_custom_emoji sticker;   /* the document of the sticker of the effect, which plays when there is no animation */
} noshi_effect;

noshi_status noshi_effects_request(noshi_arena *arena, noshi_tl_value **out);
/* the documents of the answer are matched to the ids, so a row says where to fetch the picture of its effect from.
   the effects of an answer, at most cap of them, in the order the server gave; an effect with no id or no emoji is left out. NOSHI_E_MALFORMED for an answer of another kind */
noshi_status noshi_effects_parse(const noshi_tl_value *answer, noshi_effect *rows, size_t cap, size_t *count);
/* the effect a sendMessage request goes with */
noshi_status noshi_set_effect(noshi_arena *arena, noshi_tl_value *request, int64_t effect);

#endif

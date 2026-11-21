#ifndef NOSHI_REACTION_ART_H
#define NOSHI_REACTION_ART_H

#include "noshi_messages.h"
#include "noshi_reactions.h"

/* the pictures the server draws a reaction with, from messages.getAvailableReactions. icon is the still one (static_icon), the others are lottie: appear
   (the reaction pop up of the picker), select (its press), activate (the reaction flying to the message), effect (the large burst beside it) and around (the
   short burst of a double tap). a document the answer leaves out is zeroed, its id is 0 */
typedef struct noshi_reaction_art {
    char emoji[NOSHI_REACTION_EMOJI_MAX];
    noshi_custom_emoji icon;
    noshi_custom_emoji appear;
    noshi_custom_emoji select;
    noshi_custom_emoji activate;
    noshi_custom_emoji effect;
    noshi_custom_emoji around;
} noshi_reaction_art;
/* every reaction of the answer, active or not, since an old message still shows a reaction the server has retired. a row without the emoji, or whose icon, appear, select,
   activate or effect document is missing, is NOSHI_E_MALFORMED */
noshi_status noshi_reaction_art_read(const noshi_tl_value *answer, noshi_reaction_art *items, size_t cap, size_t *count);
#endif

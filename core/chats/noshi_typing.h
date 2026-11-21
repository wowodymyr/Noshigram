#ifndef NOSHI_TYPING_H
#define NOSHI_TYPING_H

#include <stdint.h>

#include "noshi_tl.h"
#include "noshi_messages.h"

/* what the live updates say about someone typing */

typedef enum noshi_typing_action {
    NOSHI_TYPING_CANCEL = 0,
    NOSHI_TYPING_TEXT,
    NOSHI_TYPING_VOICE,       /* recording a voice message or a video message */
    NOSHI_TYPING_PHOTO,
    NOSHI_TYPING_VIDEO,
    NOSHI_TYPING_FILE,
    NOSHI_TYPING_STICKER,     /* choosing a sticker or an emoji */
    NOSHI_TYPING_OTHER        /* a game, a place, a contact, speaking in a call */
} noshi_typing_action;

typedef struct noshi_typing {
    int32_t peer_kind;          /* 1 user, 2 chat, 3 channel, as noshi_peer */
    int64_t peer_id;            /* the chat the action happens in; for kind 1 the person themselves */
    int64_t user_id;            /* who acts; zero for an anonymous sender */
    int32_t top_message;        /* the topic of a forum or the thread of a discussion, zero for the chat itself */
    noshi_typing_action action;
} noshi_typing;

/* 1 for a typing update that was read into out (peer_id, user_id and action filled), 0 for any other object or for one whose peer or action cannot be read.
   out is always initialised */
int noshi_typing_read(const noshi_tl_value *update, noshi_typing *out);
noshi_status noshi_typing_request(noshi_arena *arena, const noshi_peer_ref *peer, int cancel, noshi_tl_value **out);

#endif

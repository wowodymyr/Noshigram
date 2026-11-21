#ifndef NOSHI_UPDATES_H
#define NOSHI_UPDATES_H

#include "noshi_store.h"

/* what AyuMoments keeps of the messages the other side takes away: bits of noshi_updates.keep */
enum {
    NOSHI_KEEP_DELETED = 1,       /* a deleted message stays, under the kind of the deleted ones, in the chats the bits below name */
    NOSHI_KEEP_PRIVATE = 2,
    NOSHI_KEEP_GROUPS = 4,
    NOSHI_KEEP_CHANNELS = 8,
    NOSHI_KEEP_BOTS = 16,
    NOSHI_KEEP_EDITS = 32         /* the text before an edit stays as a version of the message */
};

typedef struct noshi_updates {
    noshi_store *store;
    int64_t account;
    int64_t gap_channel;
    int needs_difference;
    int needs_history;
    int more_difference;
    int global_gap;
    int64_t channels[128];
    uint32_t channel_count;
    uint32_t keep;
} noshi_updates;

noshi_status noshi_updates_init(noshi_updates *u, noshi_store *store, int64_t account_id);
noshi_status noshi_updates_need(noshi_updates *u, int64_t channel_id);
noshi_status noshi_updates_apply(noshi_updates *u, const noshi_tl_value *updates);
noshi_status noshi_updates_sent(noshi_updates *u, int64_t random_id, const noshi_tl_value *updates);
noshi_status noshi_updates_cache(noshi_updates *u, const noshi_tl_value *response);
noshi_status noshi_updates_state(noshi_updates *u, const noshi_tl_value *state);
noshi_status noshi_updates_difference(noshi_updates *u, int64_t channel_id, const noshi_tl_value *difference);
noshi_status noshi_updates_request(noshi_updates *u, int64_t channel_id,
                                      const noshi_tl_value *input_channel, noshi_arena *arena,
                                      noshi_tl_value **out);
noshi_status noshi_updates_cache_message(noshi_updates *u, const noshi_tl_value *message);

/* the message an updateShortMessage or updateShortChatMessage stands for, built in the arena; account is the id that stands as the sender of an outgoing one */
noshi_status noshi_updates_short_to_message(noshi_arena *arena, int64_t account, const noshi_tl_value *update, noshi_tl_value **out);
/* whether the container only carries presence, typing, draft and outbox-read updates, which cannot add a message
   or change an unread count */
int noshi_updates_quiet(const noshi_tl_value *updates);
/* 1 when the container holds an update that changes what the chat list shows although it is quiet for the notifier: the other side read our messages */
int noshi_updates_list_visible(const noshi_tl_value *updates);

#endif

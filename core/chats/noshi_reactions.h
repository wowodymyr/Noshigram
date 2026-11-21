#ifndef NOSHI_REACTIONS_H
#define NOSHI_REACTIONS_H

#include "noshi_tl.h"

#define NOSHI_REACTIONS_MAX 64
#define NOSHI_REACTION_EMOJI_MAX 32
#define NOSHI_REACTION_CATALOG_MAX 128
#define NOSHI_REACTION_PEOPLE_PAGE 50
#define NOSHI_REACTION_OFFSET_MAX 256
/* the people a chip names with their pictures instead of a number: a message with this few reactions is small enough for the
   server's recent list to hold every reactor */
#define NOSHI_REACTORS_MAX 3

/* the persisted quick reaction uses animated_<document id> for a custom emoji */
int64_t noshi_quick_reaction_document(const char *value);

typedef enum noshi_reaction_kind {
    NOSHI_REACTION_EMOJI = 1,
    NOSHI_REACTION_CUSTOM,
    NOSHI_REACTION_PAID
} noshi_reaction_kind;

typedef struct noshi_reaction {
    uint8_t kind;
    uint8_t chosen;
    int32_t chosen_order;
    int32_t count;
    int64_t document_id;
    char emoji[NOSHI_REACTION_EMOJI_MAX];
    /* users the recent list of the message names for this reaction, in list order; empty when the answer carried no list or none
       of its entries is a user */
    uint8_t reactor_count;
    int64_t reactors[NOSHI_REACTORS_MAX];
} noshi_reaction;

typedef struct noshi_reactions {
    uint8_t count;
    uint8_t min;
    noshi_reaction items[NOSHI_REACTIONS_MAX];
} noshi_reactions;

/* what a chip shows beside its emoji: the number of people, or their pictures while they are few */
typedef enum noshi_faces {
    NOSHI_FACES_NONE = 0,         /* the number */
    NOSHI_FACES_SELF_AND_OTHER,   /* private chat, both sides chose it */
    NOSHI_FACES_SELF,             /* private chat, only we did */
    NOSHI_FACES_OTHER,            /* private chat, only the other side did */
    NOSHI_FACES_REACTORS          /* the people of noshi_reaction.reactors */
} noshi_faces;

/* the faces of the chip at index of a message's reactions; a private chat has two possible reactors, so who chose
   is known from the count and the chosen flag alone */
noshi_faces noshi_reaction_faces(const noshi_reactions *all, size_t index, int private_chat);

struct noshi_peer_ref;

typedef struct noshi_reaction_person {
    int32_t peer_kind;
    int64_t peer_id;
    int32_t date;
    noshi_reaction reaction;
} noshi_reaction_person;

noshi_status noshi_reaction_people_request(noshi_arena *arena, const struct noshi_peer_ref *peer, int32_t message_id,
                                               const char *offset, noshi_tl_value **out);
noshi_status noshi_reaction_people_parse(const noshi_tl_value *answer, noshi_reaction_person *rows, size_t capacity,
                                             size_t *count, char *next, size_t next_capacity);

/* absent reactions are an empty set, malformed or oversized sets leave out empty */
noshi_status noshi_reactions_read(const noshi_tl_value *value, noshi_reactions *out);
int noshi_reaction_equal(const noshi_reaction *a, const noshi_reaction *b);
/* the catalog contains active ordinary emoji, custom and paid reactions have separate APIs */
noshi_status noshi_reaction_catalog_read(const noshi_tl_value *answer, noshi_reaction *items,
                                             size_t cap, size_t *count, int premium);
noshi_status noshi_reaction_policy_read(const noshi_tl_value *answer, noshi_reactions *allowed, int *all);
/* whether a chatFull answer lets everyone use any custom emoji as a reaction (chatReactionsAll with allow_custom) */
int noshi_reaction_policy_custom(const noshi_tl_value *answer);
/* messages.getTopReactions or, when recent is set, messages.getRecentReactions for at most limit reactions */
noshi_status noshi_reaction_list_request(noshi_arena *arena, int recent, int32_t limit, noshi_tl_value **out);
/* the custom emoji among the reactions of a messages.reactions answer, in answer order; ordinary and paid
   reactions are left out, and so is one that is malformed. messages.reactionsNotModified is NOSHI_E_NOTFOUND */
noshi_status noshi_reaction_list_read(const noshi_tl_value *answer, noshi_reaction *items, size_t cap, size_t *count);
/* one Reaction object; reactionEmpty and unknown constructors are NOSHI_E_MALFORMED */
noshi_status noshi_reaction_parse(const noshi_tl_value *value, noshi_reaction *out);
/* the Reaction object of a choice, built in arena */
noshi_status noshi_reaction_build(noshi_arena *arena, const noshi_reaction *r, noshi_tl_value **out);
noshi_status noshi_send_reactions_request(noshi_arena *arena, const struct noshi_peer_ref *peer,
                                              int32_t id, const noshi_reaction *items, size_t count,
                                              noshi_tl_value **out);
/* messages.sendPaidReaction: count stars (at least one, at most NOSHI_PAID_REACTION_MAX) sent to a message as a reaction; random_id must not be zero. The account's default privacy
   for paid reactions is kept, since none is named */
#define NOSHI_PAID_REACTION_MAX 2500
noshi_status noshi_paid_reaction_request(noshi_arena *arena, const struct noshi_peer_ref *peer, int32_t id, int32_t count, int64_t random_id, noshi_tl_value **out);
/* reactions_user_max_default and reactions_user_max_premium of help.appConfig; a key the server leaves out keeps the 1 and 3 it documents, a
   value of 0 or above NOSHI_REACTIONS_MAX is NOSHI_E_MALFORMED */
noshi_status noshi_reaction_limits_read(const noshi_tl_value *config, int32_t *standard, int32_t *premium);
/* the choices to send when pick is added to the ordinary reactions already chosen: the oldest by chosen_order go first when more than limit
   would remain, and pick is last. returns the count written to out, 0 when out is too small or arguments are bad. paid reactions in chosen
   are skipped, they are not part of the limit */
size_t noshi_reaction_choices_after_pick(const noshi_reaction *chosen, size_t count, const noshi_reaction *pick, size_t limit,
                                           noshi_reaction *out, size_t capacity);
noshi_status noshi_get_reactions_request(noshi_arena *arena, const struct noshi_peer_ref *peer,
                                             const int32_t *ids, size_t count, noshi_tl_value **out);

/* the matching reaction update in a refresh answer, NOSHI_E_NOTFOUND when none was returned */
noshi_status noshi_reaction_update_read(const noshi_tl_value *updates, int32_t peer_kind, int64_t peer_id,
                                            int32_t message_id, noshi_reactions *out);

/* a min update carries counts but omits our selection, so matching chosen_order fields survive */
noshi_status noshi_reactions_merge_min(noshi_tl_value *incoming, const noshi_tl_value *previous);

#endif

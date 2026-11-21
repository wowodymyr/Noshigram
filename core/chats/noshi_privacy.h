#ifndef NOSHI_PRIVACY_H
#define NOSHI_PRIVACY_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_messages.h"
#include "noshi_photos.h"
#include "noshi_status.h"
#include "noshi_tl.h"

/* the privacy screen: who may see each piece of the account, the people the account blocked */

typedef enum noshi_privacy_key {
    NOSHI_PRIVACY_PHONE = 0,
    NOSHI_PRIVACY_LAST_SEEN,
    NOSHI_PRIVACY_PHOTO,
    NOSHI_PRIVACY_FORWARDS,
    NOSHI_PRIVACY_CALLS,
    NOSHI_PRIVACY_INVITES,
    NOSHI_PRIVACY_VOICE,
    NOSHI_PRIVACY_ABOUT,
    NOSHI_PRIVACY_BIRTHDAY,
    NOSHI_PRIVACY_MUSIC,
    NOSHI_PRIVACY_KEY_COUNT
} noshi_privacy_key;

/* what the last rule of a list says for everybody the exceptions do not name; the server's own order of preference is nobody when it says nothing */
typedef enum noshi_privacy_base {
    NOSHI_PRIVACY_NOBODY = 0,
    NOSHI_PRIVACY_CONTACTS,
    NOSHI_PRIVACY_EVERYBODY
} noshi_privacy_base;

#define NOSHI_PRIVACY_EXCEPT_MAX 300
#define NOSHI_PRIVACY_NAME_MAX 64

typedef struct noshi_privacy_user {
    int64_t id;
    int64_t access_hash;                    /* what an input user needs to name the person again */
    char name[NOSHI_PRIVACY_NAME_MAX];
    noshi_photo_ref photo;                /* zeroed when the person has none, or when the person was added on this screen */
} noshi_privacy_user;

typedef struct noshi_privacy_chat {
    int64_t id;
    char title[NOSHI_PRIVACY_NAME_MAX];
    noshi_photo_ref photo;
} noshi_privacy_chat;

typedef struct noshi_privacy_rules {
    noshi_privacy_base base;
    /* rules the screen does not edit but must send back as they were, or the server forgets them */
    uint8_t allow_premium;
    uint8_t allow_close_friends;
    uint8_t allow_bots;
    uint8_t disallow_bots;
    size_t allow_users_count, disallow_users_count, allow_chats_count, disallow_chats_count;
    noshi_privacy_user allow_users[NOSHI_PRIVACY_EXCEPT_MAX];
    noshi_privacy_user disallow_users[NOSHI_PRIVACY_EXCEPT_MAX];
    noshi_privacy_chat allow_chats[NOSHI_PRIVACY_EXCEPT_MAX];
    noshi_privacy_chat disallow_chats[NOSHI_PRIVACY_EXCEPT_MAX];
} noshi_privacy_rules;

/* account.getPrivacy for a key; NOSHI_E_ARG for a key out of range */
noshi_status noshi_privacy_get_request(noshi_arena *arena, noshi_privacy_key key, noshi_tl_value **out);
/* an account.privacyRules answer; a list with more exceptions than the struct holds is NOSHI_E_LIMIT, since
   writing it back would drop the rest */
noshi_status noshi_privacy_parse(const noshi_tl_value *answer, noshi_privacy_rules *out);
/* account.setPrivacy with the rules as they are: the exceptions first, then what the screen does not edit, then the base */
noshi_status noshi_privacy_set_request(noshi_arena *arena, noshi_privacy_key key, const noshi_privacy_rules *rules, noshi_tl_value **out);

/* one person or chat the account blocked */
#define NOSHI_BLOCKED_MAX 200
typedef struct noshi_blocked_row {
    int32_t kind;                           /* 1 user, 2 chat, 3 channel, as noshi_peer_ref */
    int64_t id;
    int64_t access_hash;
    int32_t date;
    char name[NOSHI_PRIVACY_NAME_MAX * 2];
    noshi_photo_ref photo;
} noshi_blocked_row;

noshi_status noshi_blocked_request(noshi_arena *arena, int32_t offset, int32_t limit, noshi_tl_value **out);
/* a contacts.blocked or blockedSlice: the rows in server order, at most cap, and how many the account has in all (the length of the page for a plain
   contacts.blocked) */
noshi_status noshi_blocked_parse(const noshi_tl_value *answer, noshi_blocked_row *rows, size_t cap, size_t *count, int32_t *total);
noshi_status noshi_block_request(noshi_arena *arena, const noshi_peer_ref *peer, int block, noshi_tl_value **out);

/* the days an account may sit idle before the server deletes it; the answer is an accountDaysTTL */
noshi_status noshi_account_ttl_request(noshi_arena *arena, noshi_tl_value **out);
noshi_status noshi_account_ttl_parse(const noshi_tl_value *answer, int32_t *days);
/* 30 to 730 days as the server takes them; anything else is NOSHI_E_ARG */
noshi_status noshi_account_ttl_set_request(noshi_arena *arena, int32_t days, noshi_tl_value **out);

/* the default time of auto-delete for new chats, in seconds, zero for off */
noshi_status noshi_history_ttl_request(noshi_arena *arena, noshi_tl_value **out);
noshi_status noshi_history_ttl_parse(const noshi_tl_value *answer, int32_t *seconds);
noshi_status noshi_history_ttl_set_request(noshi_arena *arena, int32_t seconds, noshi_tl_value **out);

/* payments.clearSavedInfo: the saved card, the saved address, or both */
noshi_status noshi_clear_payments_request(noshi_arena *arena, int credentials, int info, noshi_tl_value **out);
/* contacts.resetSaved: forgets the contacts the server got from the phone */
noshi_status noshi_reset_saved_contacts_request(noshi_arena *arena, noshi_tl_value **out);

#endif

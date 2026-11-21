#ifndef NOSHI_NOTIFY_PREFS_H
#define NOSHI_NOTIFY_PREFS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_arena.h"
#include "noshi_notify_types.h"
#include "noshi_messages.h"
#include "noshi_status.h"
#include "noshi_tl.h"

/* the notification settings of an account, as the server keeps them (peerNotifySettings and its input twin) and
   the rules that turn them into a yes or a no for one chat; no I/O, so the rules are tested on the host */

/* reads a PeerNotifySettings; NULL or an object without fields is a chat with no settings of its own, all has_
   bytes zero */
noshi_status noshi_peer_notify_read(const noshi_tl_value *settings, noshi_peer_notify *out);

/* the inputPeerNotifySettings that carries the fields that have has_ set */
noshi_status noshi_peer_notify_build(noshi_arena *arena, const noshi_peer_notify *settings, noshi_tl_value **out);

/* the kinds of chat the account sets notifications for as a whole, in the order of the settings screen */
typedef enum noshi_notify_scope {
    NOSHI_SCOPE_USERS = 0,
    NOSHI_SCOPE_CHATS,
    NOSHI_SCOPE_BROADCASTS,
    NOSHI_SCOPE_COUNT
} noshi_notify_scope;

/* account.getNotifySettings of one kind of chat */
noshi_status noshi_notify_scope_request(noshi_arena *arena, noshi_notify_scope scope, noshi_tl_value **out);
/* account.getNotifySettings of one chat (a forum topic when peer->topic_id is set) */
noshi_status noshi_notify_peer_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out);
/* account.updateNotifySettings of one kind of chat (a null peer) or of one chat (a peer; a forum topic when peer->topic_id is set) */
noshi_status noshi_notify_update_request(noshi_arena *arena, int has_scope, noshi_notify_scope scope, const noshi_peer_ref *peer,
                                             const noshi_peer_notify *settings, noshi_tl_value **out);
/* the answer of an update call: a Bool, true when the server took it */
noshi_status noshi_notify_bool_result(const noshi_tl_value *answer);

/* a chat that has settings of its own: who it is and what it holds */
typedef struct noshi_notify_exception {
    int32_t peer_kind;
    int64_t peer_id;
    int64_t peer_hash;
    uint8_t deleted;
    uint8_t broadcast;          /* a channel that only its admins write in; a supergroup is a group */
    uint8_t forum_topic;        /* the entry is for a topic of a forum, which the list does not show */
    char title[128];
    noshi_peer_notify settings;
} noshi_notify_exception;

/* account.getNotifyExceptions of every chat; compare_sound asks for the chats whose sound differs, compare_stories for those whose stories differ */
noshi_status noshi_notify_exceptions_request(noshi_arena *arena, int compare_sound, int compare_stories, noshi_tl_value **out);
/* the Updates of that answer: one entry for each updateNotifySettings that names a chat, in the order given, at
   most cap */
noshi_status noshi_notify_exceptions_parse(const noshi_tl_value *answer, int64_t self_id, noshi_notify_exception *out, size_t cap, size_t *count);

/* account.resetNotifySettings and account.setContactSignUpNotification (silent true turns the news of a new contact off) */
noshi_status noshi_notify_reset_request(noshi_arena *arena, noshi_tl_value **out);
noshi_status noshi_notify_signup_request(noshi_arena *arena, int silent, noshi_tl_value **out);

/* who a reaction may come from to be announced */
typedef enum noshi_reaction_from {
    NOSHI_REACTION_FROM_NOBODY = 0,
    NOSHI_REACTION_FROM_EVERYONE,
    NOSHI_REACTION_FROM_CONTACTS
} noshi_reaction_from;

typedef struct noshi_reaction_notify {
    int32_t messages_from;      /* noshi_reaction_from */
    int32_t stories_from;
    uint8_t previews;
    noshi_notify_sound sound;
} noshi_reaction_notify;

noshi_status noshi_reaction_notify_request(noshi_arena *arena, noshi_tl_value **out);
noshi_status noshi_reaction_notify_read(const noshi_tl_value *answer, noshi_reaction_notify *out);
noshi_status noshi_reaction_notify_set_request(noshi_arena *arena, const noshi_reaction_notify *settings, noshi_tl_value **out);

/* account.getSavedRingtones: the tones of the cloud, in the order the account keeps them */
typedef struct noshi_ringtone_row {
    int64_t id;
    int64_t access_hash;
    int32_t dc;
    int32_t size;
    int32_t duration;           /* seconds, from the audio attribute; zero when the document has none */
    char title[NOSHI_SOUND_NAME_MAX];
    char file_name[NOSHI_SOUND_NAME_MAX];
    char mime[32];
    uint8_t file_reference[128];
    uint8_t file_reference_len;
} noshi_ringtone_row;

noshi_status noshi_ringtones_request(noshi_arena *arena, noshi_tl_value **out);
/* account.savedRingtones; savedRingtonesNotModified is NOSHI_E_NOTFOUND */
noshi_status noshi_ringtones_parse(const noshi_tl_value *answer, noshi_ringtone_row *rows, size_t cap, size_t *count);
/* account.saveRingtone with unsave set removes the tone from the account */
noshi_status noshi_ringtone_unsave_request(noshi_arena *arena, const noshi_ringtone_row *row, noshi_tl_value **out);

/* ---- the rules ---- */

/* what the settings of the account say, with the few switches that live on the phone only */
typedef struct noshi_notify_rules {
    noshi_peer_notify scope[NOSHI_SCOPE_COUNT];     /* users, groups, channels; unset fields mean on, shown, the default sound */
    uint8_t contact_joined;     /* announce "joined Telegram" */
    uint8_t pinned_messages;    /* announce a pinned message */
} noshi_notify_rules;

void noshi_notify_rules_init(noshi_notify_rules *rules);

typedef struct noshi_notify_decision {
    uint8_t notify;             /* announce the chat at all */
    uint8_t previews;
    noshi_notify_sound sound; /* kind NONE for a silent delivery */
} noshi_notify_decision;

/* the scope a chat of this peer kind belongs to: a user's chat is USERS, a basic group or a supergroup CHATS, a broadcast channel BROADCASTS */
noshi_notify_scope noshi_notify_scope_of(int32_t peer_kind, int is_broadcast);

/* the settings of a chat over those of its kind; a field the chat sets wins, even when it turns a muted kind on; a
   field it leaves out is the kind's */
void noshi_notify_decide(const noshi_notify_rules *rules, noshi_notify_scope scope, const noshi_peer_notify *chat, int32_t now, noshi_notify_decision *out);

/* for the settings screens: the state of a kind as the words "on", "off" or "off until", by the has_ and mute_until of the settings: 0 on, 1 off for good
   (more than a year ahead), 2 off until mute_until */
int noshi_notify_mute_state(int32_t mute_until, int32_t now);

#endif

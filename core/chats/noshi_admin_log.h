#ifndef NOSHI_ADMIN_LOG_H
#define NOSHI_ADMIN_LOG_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_channel.h"
#include "noshi_status.h"
#include "noshi_tl.h"

/* the recent actions of a group or channel: what its admins did in the last 48 hours, newest first */

#define NOSHI_ADMIN_LOG_PAGE 50
#define NOSHI_ADMIN_LOG_TEXT_MAX 512
#define NOSHI_ADMIN_LOG_NAME_MAX NOSHI_PERSON_NAME_MAX
#define NOSHI_ADMIN_LOG_QUERY_MAX 128

typedef enum noshi_admin_event_kind {
    NOSHI_LOG_OTHER = 0,          /* an action this app has no sentence for; the row says only who did something */
    NOSHI_LOG_JOIN,
    NOSHI_LOG_JOIN_BY_INVITE,
    NOSHI_LOG_JOIN_BY_REQUEST,    /* target is the admin who approved it */
    NOSHI_LOG_LEAVE,
    NOSHI_LOG_INVITE,             /* target was added by actor */
    NOSHI_LOG_BAN,                /* target cannot read the chat any more */
    NOSHI_LOG_RESTRICT,           /* target stays but lost some rights */
    NOSHI_LOG_UNBAN,
    NOSHI_LOG_PROMOTE,
    NOSHI_LOG_ADMIN_RIGHTS,       /* an admin whose rights changed */
    NOSHI_LOG_DEMOTE,
    NOSHI_LOG_EDIT_RANK,          /* old_text and new_text are the tag */
    NOSHI_LOG_TITLE,
    NOSHI_LOG_ABOUT,
    NOSHI_LOG_USERNAME,
    NOSHI_LOG_PHOTO,
    NOSHI_LOG_INVITES,            /* flag: members may add people */
    NOSHI_LOG_SIGNATURES,         /* flag */
    NOSHI_LOG_SIGNATURE_PROFILES, /* flag */
    NOSHI_LOG_HISTORY_HIDDEN,     /* flag: new members do not see the old messages */
    NOSHI_LOG_NO_FORWARDS,        /* flag */
    NOSHI_LOG_FORUM,              /* flag */
    NOSHI_LOG_ANTI_SPAM,          /* flag */
    NOSHI_LOG_SLOW_MODE,          /* new_number seconds, zero for off */
    NOSHI_LOG_HISTORY_TTL,        /* new_number seconds, zero for off */
    NOSHI_LOG_LINKED_CHAT,
    NOSHI_LOG_DEFAULT_RIGHTS,
    NOSHI_LOG_PIN,
    NOSHI_LOG_UNPIN,
    NOSHI_LOG_EDIT_MESSAGE,       /* old_text before, new_text after */
    NOSHI_LOG_DELETE_MESSAGE,
    NOSHI_LOG_SEND_MESSAGE,
    NOSHI_LOG_STOP_POLL,
    NOSHI_LOG_CALL_START,
    NOSHI_LOG_CALL_END,
    NOSHI_LOG_TOPIC_CREATE,       /* new_text is the title */
    NOSHI_LOG_TOPIC_EDIT,
    NOSHI_LOG_TOPIC_DELETE,
    NOSHI_LOG_INVITE_REVOKE,
    NOSHI_LOG_INVITE_DELETE
} noshi_admin_event_kind;

typedef struct noshi_admin_event {
    int64_t id;                     /* the next page asks for ids below the last one */
    int32_t date;                   /* unix seconds */
    uint8_t kind;                   /* noshi_admin_event_kind */
    uint8_t flag;                   /* the new value of a switch */
    uint8_t has_media;              /* the message of the event carries media; its text may be empty */
    uint8_t has_target;
    int32_t message_id;             /* of the message the event is about, zero when none */
    int32_t new_number;
    int64_t actor_id;
    int64_t target_id;
    char actor_name[NOSHI_ADMIN_LOG_NAME_MAX];
    char actor_username[NOSHI_PERSON_USERNAME_MAX];
    char target_name[NOSHI_ADMIN_LOG_NAME_MAX];
    char old_text[NOSHI_ADMIN_LOG_TEXT_MAX];
    char new_text[NOSHI_ADMIN_LOG_TEXT_MAX];
} noshi_admin_event;

/* channels.getAdminLog: one page of NOSHI_ADMIN_LOG_PAGE at most, of the events with an id below max_id (zero for the newest), matching the
   text of the query when it is not empty; limit 1 to NOSHI_ADMIN_LOG_PAGE */
noshi_status noshi_admin_log_request(noshi_arena *arena, const noshi_peer_ref *channel, const char *query, int64_t max_id, int32_t limit,
                                         noshi_tl_value **out);
/* the answer to it: events in server order, at most cap (more is NOSHI_E_LIMIT); an item that is not an event is NOSHI_E_MALFORMED, and an
   action that has no sentence here comes as NOSHI_LOG_OTHER, so a new server action cannot empty the screen */
noshi_status noshi_admin_log_parse(const noshi_tl_value *answer, noshi_admin_event *rows, size_t cap, size_t *count);

#endif

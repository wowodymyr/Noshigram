#ifndef NOSHI_NOTIFY_H
#define NOSHI_NOTIFY_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_dialogs.h"
#include "noshi_notify_prefs.h"
#include "noshi_status.h"

/* what the notification daemon shows when the app is closed; no I/O here, so the rules are tested on the host */

#define NOSHI_NOTIFY_SEEN_MAX 256
#define NOSHI_NOTIFY_EVENTS_MAX 8
#define NOSHI_NOTIFY_TITLE_MAX 128
#define NOSHI_NOTIFY_BODY_MAX (NOSHI_DIALOG_SENDER_MAX + NOSHI_DIALOG_TEXT_MAX + 8)
/* a chat whose newest message is older than this is not announced after the daemon was down, so a reboot does not bring a day of old banners */
#define NOSHI_NOTIFY_CATCHUP_SECONDS (6 * 3600)
#define NOSHI_NOTIFY_STATE_BYTES (8 + NOSHI_NOTIFY_SEEN_MAX * 16)
/* the longest line the daemon writes to a banner client */
#define NOSHI_NOTIFY_LINE_MAX (NOSHI_NOTIFY_TITLE_MAX + NOSHI_NOTIFY_BODY_MAX + 80)

typedef struct noshi_notify_settings {
    uint8_t enabled;    /* the master switch of the phone: no look, no banner */
    uint8_t russian;    /* the words of the banner are Russian, else English */
    noshi_notify_rules rules; /* the settings of the account and the few switches of the phone */
} noshi_notify_settings;

/* the newest message of each chat that was already looked at; the daemon keeps it on disk between runs */
typedef struct noshi_notify_state {
    uint32_t count;
    uint8_t baselined;  /* a first look was taken, so what it saw is not new */
    struct {
        int32_t peer_kind;
        int64_t peer_id;
        int32_t top_message;
        /* kept in memory only: the unread count at the last look, so two messages between looks are told as two */
        int32_t unread;
        uint8_t unread_known;
    } seen[NOSHI_NOTIFY_SEEN_MAX];
} noshi_notify_state;

typedef struct noshi_notify_event {
    int32_t peer_kind;
    int64_t peer_id;
    int32_t message_id;
    char title[NOSHI_NOTIFY_TITLE_MAX];
    char body[NOSHI_NOTIFY_BODY_MAX];
    /* the tone the chat asks for; kind NONE is a banner without a sound */
    noshi_notify_sound sound;
    /* how many messages came in the chat since the last look, at least one */
    int32_t count;
} noshi_notify_event;

void noshi_notify_state_init(noshi_notify_state *state);

/* the tone of the app that one person always gets: the file of the bundle when a message of this user id is announced, NULL for a person with none of their own */
const char *noshi_notify_user_tone(int64_t user_id);

/* looks at the chat list the server just gave (newest first) and says which chats got a message worth a banner
   since the last look */
noshi_status noshi_notify_diff(noshi_notify_state *state, const noshi_notify_settings *settings, const noshi_dialog_row *rows, size_t row_count,
                                   int32_t now, int32_t active_peer_kind, int64_t active_peer_id, noshi_notify_event *events, size_t cap,
                                   size_t *count, size_t *more_suppressed);

/* the summary line for what did not fit: "and N more messages" in the language of the settings */
void noshi_notify_more_text(const noshi_notify_settings *settings, size_t more, char *out, size_t cap);

/* the state as bytes for a file, and back. unpack rejects wrong magic, version and counts and leaves a fresh state then */
noshi_status noshi_notify_state_pack(const noshi_notify_state *state, uint8_t *out, size_t cap, size_t *len);
noshi_status noshi_notify_state_unpack(const uint8_t *data, size_t len, noshi_notify_state *out);

/* one event as a text line: "N", the peer kind, peer id and message id, then the title and the body, tab
   separated, ended with a newline */
noshi_status noshi_notify_line_encode(const noshi_notify_event *event, char *out, size_t cap, size_t *len);
/* the reverse, for a line without its newline; NOSHI_E_MALFORMED for anything else */
noshi_status noshi_notify_line_decode(const char *line, size_t len, noshi_notify_event *out);

#endif

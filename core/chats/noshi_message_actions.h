#ifndef NOSHI_MESSAGE_ACTIONS_H
#define NOSHI_MESSAGE_ACTIONS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_messages.h"
#include "noshi_tl.h"

/* requests a change of sharing, or answers a request when request_id is positive */
noshi_status noshi_sharing_request(noshi_arena *arena, const noshi_peer_ref *peer, int enabled, int32_t request_id, noshi_tl_value **out);
/* the same switch for a group or a channel: enabled stops members from forwarding, copying and saving what the chat holds; only its creator may set it */
noshi_status noshi_chat_sharing_request(noshi_arena *arena, const noshi_peer_ref *peer, int enabled, noshi_tl_value **out);

#define NOSHI_SHARING_PERIOD_DEFAULT 86400
noshi_status noshi_sharing_period_parse(const noshi_tl_value *answer, int32_t *seconds);
/* the server's expired bit wins; the deadline is inclusive as in Telegram */
int noshi_sharing_expired(int server_expired, int32_t date, int32_t period, int64_t now);

/* a covered part of a code span must be revealed before the whole span can be copied */
int noshi_code_has_hidden_spoiler(size_t offset, size_t length, const noshi_entity *entities, size_t count);

typedef enum noshi_read_action {
    NOSHI_READ_AUTOMATIC,
    NOSHI_READ_EXPLICIT,
    NOSHI_READ_ONCE
} noshi_read_action;
int noshi_read_action_allowed(int ghost, noshi_read_action action);

/* what a long press on a message can offer; the rules below pick the ones that can work */
typedef enum noshi_message_action {
    NOSHI_ACTION_REACT = 1 << 0,
    NOSHI_ACTION_REPLY = 1 << 1,
    NOSHI_ACTION_COPY = 1 << 2,
    NOSHI_ACTION_COPY_LINK = 1 << 3,
    NOSHI_ACTION_EDIT = 1 << 4,
    NOSHI_ACTION_FORWARD = 1 << 5,
    NOSHI_ACTION_PIN = 1 << 6,
    NOSHI_ACTION_UNPIN = 1 << 7,
    NOSHI_ACTION_DELETE = 1 << 8,
    NOSHI_ACTION_DETAILS = 1 << 9,
    NOSHI_ACTION_REPEAT = 1 << 10,
    NOSHI_ACTION_SAVE = 1 << 11,
    NOSHI_ACTION_GALLERY = 1 << 12,   /* the photo or video goes to the photo library of the phone */
    NOSHI_ACTION_SELECT = 1 << 13,    /* starts the selection of several messages */
    NOSHI_ACTION_TRANSCRIBE = 1 << 14,    /* the words of a voice message, as text */
    NOSHI_ACTION_BOOKMARK = 1 << 15,      /* keeps the message in the list of bookmarks of this phone */
    NOSHI_ACTION_UNBOOKMARK = 1 << 16,
    NOSHI_ACTION_TRANSLATE = 1 << 17,     /* the words of the message, in the language the person reads */
    NOSHI_ACTION_COPY_PHOTO = 1 << 18,    /* the picture of a photo goes to the pasteboard */
    NOSHI_ACTION_HISTORY = 1 << 19,       /* everything the sender of the message wrote in this group */
    NOSHI_ACTION_REPORT = 1 << 20,        /* messages.report for a message of somebody else */
    NOSHI_ACTION_FORWARD_HIDDEN = 1 << 21,    /* forward without the name of the author */
    NOSHI_ACTION_REMIND = 1 << 22,            /* a reminder about the message arrives in the favorites at a time the person picks */
    NOSHI_ACTION_REPLY_PRIVATE = 1 << 23,     /* the sender of a group message is written to in a chat of their own */
    NOSHI_ACTION_EDIT_HISTORY = 1 << 24,      /* what the message said before its edits; the client adds it, since only it knows whether the versions were kept */
    NOSHI_ACTION_REACTORS = 1 << 25,         /* the people and dates of a message's reactions */
    NOSHI_ACTION_SELECT_TEXT = 1 << 26,      /* the words are selected in the bubble, to copy or to quote */
    NOSHI_ACTION_STATISTICS = 1 << 27,       /* the graphs and the public forwards of a post of a channel the account administers */
    NOSHI_ACTION_SAVE_MUSIC = 1 << 28        /* the song goes on the profile of the account */
} noshi_message_action;

typedef struct noshi_action_context {
    int32_t peer_kind;          /* 1 user, 2 chat, 3 channel */
    int32_t message_id;         /* zero or less for a message that has not been sent yet */
    uint8_t broadcast;          /* the chat is a broadcast channel, where only its admins write */
    uint8_t can_post;           /* the account may post in that broadcast channel */
    uint8_t outgoing;
    uint8_t service;
    uint8_t has_text;
    uint8_t has_entities;       /* bold, links and the like, which a plain field cannot give back */
    noshi_preview_kind media; /* none or text for a message of words alone */
    uint8_t reactions_possible;
    uint8_t has_username;       /* the chat is public, so a message has a link without asking the server */
    uint8_t pinned_now;         /* this message is the one pinned in the chat */
    uint8_t bookmarked;         /* the message is in the bookmarks already */
    uint8_t media_fetchable;    /* the media has a file the app can download, which saving it to the library needs */
    uint8_t translate_wanted;   /* the translate button is on in the settings and the language of the words is not one the person left alone */
    uint8_t saved_chat;         /* the chat is the favorites, where saving a message again would only copy it onto itself */
    uint8_t sender_user;        /* the message was written by a person the app can search for (a user with a hash) */
    uint8_t admin;              /* the account owns or administers the broadcast channel */
    uint8_t can_view_stats;     /* the server named the statistics readable by this account, which it does not for an admin of a small channel or one without the right */
    uint8_t forwarded;          /* the message carries a forward header */
    uint8_t music_saveable;     /* the message is a song with a file the server can put on the profile */
    int32_t views;              /* what the server counted for a channel post */
    int32_t forwards;
} noshi_action_context;

/* the actions that apply, as a mask of noshi_message_action; a message not sent yet can only be copied, a
   service line has none */
uint32_t noshi_message_actions_for(const noshi_action_context *context);

#define NOSHI_TRANSCRIPT_MAX 4100

/* what messages.transcribedAudio says: the text so far, whether the server is still listening, and the id that later updates carry */
typedef struct noshi_transcript {
    uint8_t pending;
    int64_t id;
    char text[NOSHI_TRANSCRIPT_MAX];
} noshi_transcript;

/* messages.transcribeAudio for a voice message of a chat */
noshi_status noshi_transcribe_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t message_id, noshi_tl_value **out);
/* the answer: NOSHI_OK with the text (cut at a character boundary when it is longer than
   NOSHI_TRANSCRIPT_MAX), NOSHI_E_MALFORMED for anything else. out is always initialised */
noshi_status noshi_transcribe_parse(const noshi_tl_value *answer, noshi_transcript *out);

/* messages.getOutboxReadDate: when the other side of a private chat read a message of ours */
noshi_status noshi_read_date_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t message_id, noshi_tl_value **out);
/* the outboxReadDate it answers: its date, unix seconds; NOSHI_E_MALFORMED for anything else or a date that is
   not positive; date is zero then */
noshi_status noshi_read_date_parse(const noshi_tl_value *answer, int32_t *date);
noshi_status noshi_group_read_dates_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t message_id, noshi_tl_value **out);
typedef struct noshi_group_read_date {
    int64_t user_id;
    int32_t date;
} noshi_group_read_date;
noshi_status noshi_group_read_dates_parse(const noshi_tl_value *answer, noshi_group_read_date *rows, size_t capacity, size_t *count);

/* what a set of selected messages can do together, from the mask each one has; copy when any of them has words to
   copy, and forward and delete only when every one of them allows it, since one that does not would make the whole
   request fail */
uint32_t noshi_selection_actions(const uint32_t *masks, size_t count);

int noshi_copy_forward_allowed(noshi_preview_kind kind, int has_text, int has_file, int view_once, int64_t size, int32_t duration);

/* at most NOSHI_MESSAGES_MAX messages in one request */

/* messages.deleteMessages for a user or basic chat, channels.deleteMessages for a channel. revoke deletes for the other side too,
   and is ignored for a channel, where a delete always reaches everyone */
noshi_status noshi_delete_messages_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count,
                                               int revoke, noshi_tl_value **out);
/* the answer to either: NOSHI_OK for messages.affectedMessages, NOSHI_E_MALFORMED for anything else */
noshi_status noshi_delete_messages_parse(const noshi_tl_value *answer);

/* messages.updatePinnedMessage */
noshi_status noshi_pin_message_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, int unpin, noshi_tl_value **out);

/* messages.editMessage with a new text and no entities; an empty text is NOSHI_E_ARG, the server would not take
   it either */
noshi_status noshi_edit_message_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, const char *text,
                                            noshi_tl_value **out);

/* the same for the caption of a message that carries media: no media field is sent, so the picture or the file stays, and an empty text takes the caption away */
noshi_status noshi_edit_caption_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t id, const char *text,
                                            noshi_tl_value **out);

/* messages.forwardMessages of ids from one chat into another, one random id for each. drop_author sends them as if they were written by the
   forwarder, without the line about where they came from */
noshi_status noshi_forward_messages_request(noshi_arena *arena, const noshi_peer_ref *from, const noshi_peer_ref *to,
                                                const int32_t *ids, const int64_t *random_ids, size_t count, int drop_author,
                                                noshi_tl_value **out);

#endif

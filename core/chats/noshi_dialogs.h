#ifndef NOSHI_DIALOGS_H
#define NOSHI_DIALOGS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_media_ref.h"
#include "noshi_notify_types.h"
#include "noshi_people.h"
#include "noshi_photos.h"
#include "noshi_tl.h"

#define NOSHI_DIALOGS_MAX 200
#define NOSHI_DIALOG_TITLE_MAX 128
#define NOSHI_DIALOG_SENDER_MAX 64
#define NOSHI_DIALOG_TEXT_MAX 4096
#define NOSHI_DIALOG_EMOJI_MAX 8

typedef enum noshi_dialog_kind {
    NOSHI_DIALOG_USER = 1,
    NOSHI_DIALOG_BOT,
    NOSHI_DIALOG_GROUP,
    NOSHI_DIALOG_CHANNEL
} noshi_dialog_kind;

typedef enum noshi_preview_kind {
    NOSHI_PREVIEW_NONE = 0,
    NOSHI_PREVIEW_TEXT,
    NOSHI_PREVIEW_PHOTO,
    NOSHI_PREVIEW_VIDEO,
    NOSHI_PREVIEW_VIDEO_MESSAGE,
    NOSHI_PREVIEW_VOICE,
    NOSHI_PREVIEW_AUDIO,
    NOSHI_PREVIEW_STICKER,
    NOSHI_PREVIEW_GIF,
    NOSHI_PREVIEW_FILE,
    NOSHI_PREVIEW_LOCATION,
    NOSHI_PREVIEW_CONTACT,
    NOSHI_PREVIEW_POLL,
    NOSHI_PREVIEW_SERVICE,
    NOSHI_PREVIEW_OTHER,
    NOSHI_PREVIEW_PAID,   /* paid media that is still locked: only the size is known, the file comes with the payment */
    NOSHI_PREVIEW_STORY,  /* a story sent into the chat: the message only names it */
    NOSHI_PREVIEW_DICE    /* an animated game emoji (dice, darts, basketball, football, bowling, slots) thrown into the chat; alt is the emoji and dice_value the result */
} noshi_preview_kind;

/* one chat list row; text is UTF-8 cut at a character boundary with line breaks turned into spaces */
/* a custom emoji of the preview text: where it stands in UTF-16 units of the text field, and the document that draws it */
typedef enum {
    NOSHI_SEND_OPEN = 0,
    NOSHI_SEND_BAN_GROUP,     /* the admins barred every member from messages */
    NOSHI_SEND_BAN_ACCOUNT    /* the admins barred this account, until a date or for good */
} noshi_send_ban;

typedef struct noshi_dialog_emoji {
    uint16_t offset;
    uint16_t length;
    int64_t document;
} noshi_dialog_emoji;

typedef struct noshi_dialog_row {
    uint8_t noforwards;
    int32_t peer_kind;      /* 1 user, 2 chat, 3 channel, as noshi_peer */
    int64_t peer_id;
    noshi_dialog_kind kind;
    uint8_t contact;
    uint8_t saved;          /* the chat with oneself */
    uint8_t deleted;
    uint8_t verified;
    uint8_t premium;        /* the user of a private chat has Telegram Premium */
    int64_t emoji_status;       /* the custom emoji document the user shows after their name, zero without one */
    int32_t emoji_status_until; /* unix time it ends, zero when it has none */
    uint8_t pinned;
    uint8_t muted;
    /* the settings the chat sets itself, which stand over those of its kind; muted above is only its own mute */
    noshi_peer_notify notify;
    uint8_t can_post;       /* a broadcast channel the account may post in: its creator, or an admin allowed to post */
    uint8_t admin;          /* a broadcast channel the account owns or is an admin of, with any rights: the statistics of its posts are open to it */
    uint8_t send_ban;       /* a group the account may not write in, as noshi_send_ban says why */
    int32_t send_ban_until; /* unix time a personal ban ends; zero is for good */
    uint8_t unread_mark;
    uint8_t outgoing;       /* the last message is ours */
    uint8_t forwarded;      /* the last message carries a forward header, which the list marks with an arrow before the preview */
    uint8_t read;           /* and the other side has read it */
    uint8_t sender_is_self;
    uint8_t folder;         /* the archive entry of the chat list, not a chat */
    uint8_t forum;          /* a supergroup whose chat is split into topics */
    uint8_t community;      /* a community: a set of chats the server lists as one entry; peer_id is its id */
    uint8_t community_collapsed;    /* the account asked to see the community as one chat in its list */
    /* a chat or bot that was added to a community: its id, and the access hash and title of the community when the answer carries it; zero without one */
    int64_t linked_community_id;
    int64_t linked_community_hash;
    char linked_community_title[NOSHI_DIALOG_TITLE_MAX];
    uint8_t left;           /* the account is not a member of this group or channel */
    uint8_t join_to_send;   /* the group lets only its members write, which includes the comments of the channel it is linked to */
    /* a topic row: the forum above names the peer fields, topic_id the thread (1 is General) */
    int32_t topic_id;
    int64_t topic_icon_emoji;   /* the custom emoji document of the icon, zero for the plain colored hash */
    int32_t topic_icon_color;   /* 0xRRGGBB of the plain icon */
    uint8_t topic_closed;
    int32_t folder_id;
    int64_t peer_hash;      /* the access hash an input peer needs; zero for a basic group */
    int32_t top_message;
    int32_t read_inbox_max_id;  /* everything up to this id of theirs we have read */
    int32_t read_outbox_max_id; /* everything up to this id of ours they have read */
    int32_t date;
    int32_t unread_count;
    int32_t mentions;
    int32_t reactions;      /* messages of ours that got a reaction we have not seen */
    int32_t participants_count;
    noshi_preview_kind preview;
    /* a small picture of the photo, video, gif or round video of the last message, for the chat list; source none for everything else */
    noshi_media_ref thumb;
    uint8_t service;        /* for a service message: noshi_service_kind + 1, with its text and number below */
    int32_t service_value;
    uint8_t service_actor_is_target;
    char service_target[NOSHI_DIALOG_SENDER_MAX];
    noshi_presence presence;  /* of the other side of a user chat, unknown for the rest */
    int32_t seen;
    noshi_photo_ref photo;
    char title[NOSHI_DIALOG_TITLE_MAX];
    /* who wrote the last message when it was not a user chat; empty otherwise */
    char sender[NOSHI_DIALOG_SENDER_MAX];
    /* the user behind that name and the photo of the user, for the small picture before the preview; zero when the name is empty or the user has no photo */
    int64_t sender_id;
    noshi_photo_ref sender_photo;
    /* the message text, a caption, a sticker emoji or a file name; empty when the kind says it all */
    char text[NOSHI_DIALOG_TEXT_MAX];
    /* the custom emoji inside text, in order; none for a text that is not the message itself */
    uint8_t emoji_count;
    noshi_dialog_emoji emoji[NOSHI_DIALOG_EMOJI_MAX];
} noshi_dialog_row;

/* the last-message part of a row (top_message, date, outgoing, preview, text, sender) made from one live message, for a chat the account already lists; the rest of the row is zero.
   kind says whether the sender is named, as it is in a group and not in a private chat; NOSHI_E_MALFORMED for anything that is not a message with an id and a peer */
noshi_status noshi_dialog_message_row(const noshi_tl_value *message, const noshi_tl_value *users, const noshi_tl_value *chats, int64_t self_id,
                                          noshi_dialog_kind kind, noshi_dialog_row *row);

/* fills the title, photo, hash and kind of a row whose peer_kind and peer_id are set, from the users and chats of an answer;
   a peer the answer does not carry is left with an empty title (a user is then marked deleted) */
void noshi_dialog_peer_read(noshi_dialog_row *row, const noshi_tl_value *users, const noshi_tl_value *chats, int64_t self_id);

/* what a global search looks through: every message, only the posts of channels, or one kind of attachment */
typedef enum noshi_search_kind {
    NOSHI_SEARCH_ALL = 0,
    NOSHI_SEARCH_POSTS,
    NOSHI_SEARCH_MEDIA,
    NOSHI_SEARCH_LINKS,
    NOSHI_SEARCH_FILES,
    NOSHI_SEARCH_MUSIC,
    NOSHI_SEARCH_VOICE
} noshi_search_kind;

/* reads a messages.messages, messagesSlice or channelMessages answer to a global search */
noshi_status noshi_search_parse(const noshi_tl_value *answer, int64_t self_id, noshi_dialog_row *rows, size_t cap,
                                    size_t *count, int32_t *next_rate);

/* contacts.search for the text over every public user, bot, group and channel; limit is 1 to NOSHI_DIALOGS_MAX */
noshi_status noshi_found_request(noshi_arena *arena, const char *query, int32_t limit, noshi_tl_value **out);
/* reads a contacts.found answer: first the chats the account already has with the text, then the public ones, each
   peer once, at most cap rows */
noshi_status noshi_found_parse(const noshi_tl_value *answer, int64_t self_id, noshi_dialog_row *rows, size_t cap, size_t *count);

/* reads a messages.dialogs or messages.dialogsSlice answer in server order, at most cap rows. self_id marks the
   saved messages chat, now (unix seconds) decides which mutes are still running */
noshi_status noshi_dialogs_parse(const noshi_tl_value *answer, int64_t self_id, int32_t now,
                                     noshi_dialog_row *rows, size_t cap, size_t *count);

/* messages.getSavedDialogs: the favorites split by the chat each message came from, newest first, up to limit (1
   to NOSHI_DIALOGS_MAX), pinned ones included */
noshi_status noshi_saved_dialogs_request(noshi_arena *arena, int32_t offset_date, int32_t offset_id, int32_t offset_peer_kind, int64_t offset_peer_id,
                                             int64_t offset_peer_hash, int32_t limit, noshi_tl_value **out);

/* what the header of a community screen needs besides its chats */
#define NOSHI_COMMUNITY_ABOUT_MAX 256
typedef struct noshi_community_info {
    char title[NOSHI_DIALOG_TITLE_MAX];
    char about[NOSHI_COMMUNITY_ABOUT_MAX];
    uint8_t collapsed;      /* shown as one chat in the list */
    noshi_photo_ref photo;
} noshi_community_info;

/* reads the messages.chatFull answer to channels.getFullChannel for a community: its title, description and list
   state in info, and one row per chat it links in server order, at most cap rows */
noshi_status noshi_community_parse(const noshi_tl_value *answer, noshi_community_info *info, noshi_dialog_row *rows,
                                       size_t cap, size_t *count);

/* adds live dialog state without losing community order, membership or peer metadata */
noshi_status noshi_community_previews_apply(const noshi_tl_value *answer, int64_t self_id, int32_t now,
                                               noshi_dialog_row *rows, size_t count);

/* communities.toggleCommunityCollapsedInDialogs: collapsed shows the community as one chat in the account's list */
noshi_status noshi_community_collapse_request(noshi_arena *arena, int64_t id, int64_t access_hash, int collapsed, noshi_tl_value **out);

/* messages.getForumTopics for a forum: offset_date, offset_id and offset_topic are zero for the first page and the
   date */
noshi_status noshi_topics_request(noshi_arena *arena, int32_t peer_kind, int64_t peer_id, int64_t peer_hash, int32_t offset_date,
                                      int32_t offset_id, int32_t offset_topic, int32_t limit, noshi_tl_value **out);

/* reads a messages.forumTopics answer into one row per topic in server order (pinned first, then by last message),
   at most cap rows. forum is the row of the forum itself */
noshi_status noshi_topics_parse(const noshi_tl_value *answer, const noshi_dialog_row *forum, int64_t self_id, int32_t now,
                                    noshi_dialog_row *rows, size_t cap, size_t *count);

/* what the chat list shows of a forum that the forum's own row does not carry: the topic its last message is in, and the unread counts of all topics, since the
   count the server keeps on the forum row follows the General topic alone and stays high after every topic was read */
typedef struct {
    int32_t topic_id;           /* zero when no topic matches the last message */
    int64_t topic_icon_emoji;
    int32_t topic_icon_color;
    char topic_title[NOSHI_DIALOG_TITLE_MAX];
    /* the topic with the next newest message, which the row shows beside the first; zero when the forum has no second one */
    int32_t second_topic_id;
    int64_t second_icon_emoji;
    int32_t second_icon_color;
    char second_title[NOSHI_DIALOG_TITLE_MAX];
    int32_t unread_count;
    int32_t mentions;
    int32_t reactions;
} noshi_forum_summary;

/* folds the rows of noshi_topics_parse into one summary; last_message is the top message of the forum row, and the topic that holds it is named,
   or the one with the newest message when none holds it exactly; the second is the newest of the rest */
noshi_status noshi_forum_summarize(const noshi_dialog_row *topics, size_t count, int32_t last_message, noshi_forum_summary *out);

/* folder-filtered getDialogs may omit dialogFolder, but archive remains a valid destination */
noshi_status noshi_dialogs_ensure_archive(noshi_dialog_row *rows, size_t cap, size_t *count);

/* folder metadata supplies total unread chats; only names from folder 1 form its preview */
noshi_status noshi_archive_summary_parse(const noshi_tl_value *info, const noshi_tl_value *contents,
                                              int64_t self_id, int32_t now, noshi_dialog_row *out);

#endif

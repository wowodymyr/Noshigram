#ifndef NOSHI_MESSAGES_H
#define NOSHI_MESSAGES_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_dialogs.h"
#include "noshi_gift.h"
#include "noshi_media.h"
#include "noshi_reactions.h"
#include "noshi_poll.h"
#include "noshi_tl.h"
#include "noshi_voice.h"

#define NOSHI_MESSAGES_MAX 100
#define NOSHI_MESSAGE_TEXT_MAX (4 * 4096 + 4)
/* a post with a line of custom emoji, a few links and nested styles passes fifty entities, and the ones past the cap were dropped: the last emoji stayed plain characters */
#define NOSHI_MESSAGE_ENTITIES_MAX 100
#define NOSHI_MESSAGE_URLS_MAX 1024
#define NOSHI_STICKERS_MAX 400
#define NOSHI_STICKER_SETS_MAX 200
#define NOSHI_ANIMATED_EMOJI_MAX 1024
#define NOSHI_ANIMATED_EMOJI_BYTES_MAX (512 * 1024)

typedef enum noshi_entity_kind {
    NOSHI_ENTITY_BOLD = 1,
    NOSHI_ENTITY_ITALIC,
    NOSHI_ENTITY_UNDERLINE,
    NOSHI_ENTITY_STRIKE,
    NOSHI_ENTITY_CODE,
    NOSHI_ENTITY_URL,         /* the text is the address */
    NOSHI_ENTITY_TEXT_URL,    /* the address is in the url pool */
    NOSHI_ENTITY_EMAIL,
    NOSHI_ENTITY_MENTION,
    NOSHI_ENTITY_HASHTAG,
    NOSHI_ENTITY_CUSTOM_EMOJI, /* the text is the emoji it stands for, document_id draws it */
    NOSHI_ENTITY_BOT_COMMAND, /* "/start" or "/start@bot", a command a tap sends */
    NOSHI_ENTITY_SPOILER,
    NOSHI_ENTITY_PRE,         /* a block of code, its language (maybe empty) in the url pool */
    NOSHI_ENTITY_BLOCKQUOTE,  /* flags: NOSHI_ENTITY_COLLAPSED */
    NOSHI_ENTITY_MENTION_NAME, /* a name that opens the profile of user_id, whatever the words say */
    NOSHI_ENTITY_FORMATTED_DATE /* the words stand for the moment date, shown as the flags ask */
} noshi_entity_kind;

/* flags of an entity: a quote that starts folded, and the shapes a formatted date takes (none set means the plain date and time) */
enum {
    NOSHI_ENTITY_COLLAPSED = 1,
    NOSHI_DATE_RELATIVE = 1,
    NOSHI_DATE_SHORT_TIME = 2,
    NOSHI_DATE_LONG_TIME = 4,
    NOSHI_DATE_SHORT_DATE = 8,
    NOSHI_DATE_LONG_DATE = 16,
    NOSHI_DATE_DAY_OF_WEEK = 32
};

/* offsets and lengths count UTF-16 units, as the server sends them and as NSString counts */
typedef struct noshi_entity {
    uint8_t kind;
    int32_t offset;
    int32_t length;
    int16_t url_offset;     /* into noshi_message_row.urls, -1 without one */
    int16_t url_length;
    int64_t document_id;    /* custom emoji only */
    int64_t user_id;        /* mention name only */
    int32_t date;           /* formatted date only, seconds since 1970 */
    uint8_t flags;
} noshi_entity;

/* reads the entities shared by a message and a textWithEntities, with a bounded url pool */
void noshi_entities_read(const noshi_tl_value *value, noshi_entity *entities, size_t capacity,
                           char *urls, size_t urls_capacity, uint8_t *count);

/* an entity of a message being sent. text is the address of a text link or the language of a block of code (NULL
   or empty for none) and only has to live through the call */
typedef struct noshi_send_entity {
    uint8_t kind;
    uint8_t flags;
    int32_t offset;
    int32_t length;
    int64_t id;
    int64_t access_hash;
    int32_t date;
    const char *text;
} noshi_send_entity;

typedef enum noshi_service_kind {
    NOSHI_SERVICE_OTHER = 0,
    NOSHI_SERVICE_CHAT_CREATE,
    NOSHI_SERVICE_TITLE,
    NOSHI_SERVICE_PHOTO_CHANGED,
    NOSHI_SERVICE_PHOTO_DELETED,
    NOSHI_SERVICE_USER_ADDED,
    NOSHI_SERVICE_USER_REMOVED,
    NOSHI_SERVICE_JOINED,
    NOSHI_SERVICE_CHANNEL_CREATE,
    NOSHI_SERVICE_PIN,
    NOSHI_SERVICE_CALL,
    NOSHI_SERVICE_GIFT,
    NOSHI_SERVICE_CONTACT_JOINED,
    NOSHI_SERVICE_SCREENSHOT,
    NOSHI_SERVICE_HISTORY_CLEAR,
    NOSHI_SERVICE_MIGRATED,         /* text names the group it was upgraded from, empty for the group that was upgraded */
    NOSHI_SERVICE_CUSTOM,           /* text is the whole line, as a bot or the server wrote it */
    NOSHI_SERVICE_VIDEO_CHAT,       /* value is the length in seconds of a video chat that ended, zero while one starts */
    NOSHI_SERVICE_VIDEO_CHAT_INVITE,
    NOSHI_SERVICE_TOPIC_CREATE,
    NOSHI_SERVICE_TOPIC_EDIT,       /* text is the new title when it changed; value is 1 for closed, 2 for reopened */
    NOSHI_SERVICE_TTL,              /* value is the auto-delete period in seconds, zero when it was turned off */
    NOSHI_SERVICE_BOOST,
    NOSHI_SERVICE_PAYMENT,
    NOSHI_SERVICE_BOT_ALLOWED,
    NOSHI_SERVICE_PREMIUM_GIFT,     /* value is the number of months; the gift of a Premium subscription or a gift code */
    NOSHI_SERVICE_THEME,            /* text is the emoji of the new theme of the chat, empty when the theme was taken off */
    NOSHI_SERVICE_WALLPAPER,
    NOSHI_SERVICE_PHOTO_SUGGESTED,
    NOSHI_SERVICE_GAME_SCORE,       /* value is the score */
    NOSHI_SERVICE_GIVEAWAY,
    NOSHI_SERVICE_GIVEAWAY_RESULTS, /* value is the number of winners */
    NOSHI_SERVICE_PAYMENT_REFUNDED,
    NOSHI_SERVICE_SHARING_REQUEST, /* value bits: previous, requested, expired */
    NOSHI_SERVICE_SHARING_TOGGLE,  /* value bits: previous, new */
    NOSHI_SERVICE_POLL_ANSWER_ADDED,   /* text is the answer a person added to a poll */
    NOSHI_SERVICE_POLL_ANSWER_REMOVED, /* text is the answer a person took out of a poll */
    NOSHI_SERVICE_COMMUNITY,           /* value bits: 1 taken out of the community, 2 no person acted (the chat itself or a channel post); the community is service_community */
    NOSHI_SERVICE_STARS_GIFT           /* value is the number of Stars given, capped at INT32_MAX; the gift of a Stars balance, not a collectible gift */
} noshi_service_kind;

/* how a call ended, as the server says: nothing for a call that was talked through and hung up */
typedef enum noshi_call_outcome {
    NOSHI_OUTCOME_ENDED = 0,
    NOSHI_OUTCOME_MISSED,
    NOSHI_OUTCOME_BUSY,
    NOSHI_OUTCOME_DISCONNECTED
} noshi_call_outcome;

/* a messageAction as the kind plus one, the line it carries in text, a number in value and the user it names in
   target */
uint8_t noshi_service_summary(const noshi_tl_value *action, char *text, size_t cap, int32_t *value, int64_t *target);

typedef struct noshi_message_row {
    int32_t id;
    int32_t date;
    int32_t edit_date;
    uint8_t edit_hide;          /* the server changed the message (a reaction, a vote) and asks that it is not shown as edited, whatever edit_date says */
    int32_t reply_peer_kind;   /* zero when the original is in this chat */
    int64_t reply_peer_id;
    char reply_quote[1024];
    int32_t reply_story;        /* id of the story this message answers, zero when it answers none; the story is of the other person in a private chat when we wrote it */
    int32_t reply_to;           /* id of the replied message, zero without one, or when it is only the root of its forum topic */
    int32_t topic_id;           /* the forum topic it belongs to; 1 (General) for a message with no topic header */
    int32_t thread_id;          /* the top reply in a discussion, or the direct reply when there is no top */
    int64_t from_id;            /* the user who wrote it, zero for a channel post or an anonymous sender */
    int64_t from_channel;       /* the channel it was written as in a group, zero when a user wrote it */
    int64_t target_id;          /* the user a service message is about */
    int64_t service_community;  /* the community a chat was added to, zero when it was taken out; for NOSHI_SERVICE_COMMUNITY */
    uint8_t out;
    uint8_t noforwards;
    uint8_t invert_media;       /* the sender asked for the words above the picture or the file instead of under it */
    uint8_t unread_mention;
    uint8_t media_unread;       /* a voice note or a round video that nobody has played yet: the person for an incoming one, the other side for one of ours */
    uint8_t post;
    uint8_t forwarded;
    int32_t saved_peer_kind;    /* in the favorites: the chat the message came from (the account itself for its own notes); zero elsewhere */
    int64_t saved_peer_id;
    uint8_t forward_saved_out;  /* the header says the copy in the favorites was written by the account itself */
    uint8_t service;            /* noshi_service_kind + 1, zero for an ordinary message */
    int32_t service_value;      /* the number some service kinds carry, see noshi_service_kind */
    uint8_t entity_count;
    char forward_name[NOSHI_DIALOG_SENDER_MAX];
    int64_t grouped_id;         /* the album the message is a part of, zero for a message of its own */
    int32_t forward_date;       /* when the original was written, unix seconds; zero when the header has none */
    int64_t forward_from;       /* who wrote a forwarded message, when the header says */
    int32_t forward_origin_kind;    /* the chat a forward header names as the place of the message (saved_from_peer): the replies chat points at the comment this way */
    int64_t forward_origin_id;
    int32_t forward_origin_message; /* and the message in it (saved_from_msg_id), zero when the header has none */
    uint8_t call_reason;        /* a call service message: noshi_call_outcome */
    uint8_t call_video;         /* and whether the call had video; the length in seconds is service_value */
    char from_rank[128];
    char post_author[NOSHI_DIALOG_SENDER_MAX];   /* the name an administrator signed a channel post with, empty for a post that has none */
    noshi_media_info media;
    noshi_gift gift;          /* a gift service message: the gift, with its note in text */
    noshi_reactions reactions;
    uint8_t reactions_possible;
    int64_t via_bot_id;         /* the bot whose inline result this message is, zero otherwise */
    int64_t effect_id;          /* the animated effect the message was sent with (see noshi_effects.h), zero for none */
    uint8_t has_markup;         /* buttons or a keyboard came with it; noshi_markup_read of the message's reply_markup tells which */
    uint8_t has_reactions;
    int32_t views;              /* how many saw a channel post, zero when the server did not count */
    int32_t forwards;           /* how many times a channel post was forwarded, zero when the server did not count */
    uint8_t has_comments;       /* a channel post that has a comment thread in its discussion group */
    int32_t comments;           /* the comments so far */
    int64_t discussion_id;      /* the discussion group (a channel id), zero when unknown */
    uint8_t commenter_count;
    int64_t commenters[3];      /* the newest commenters, most recent first, users only */
    noshi_entity entities[NOSHI_MESSAGE_ENTITIES_MAX];
    /* the poll of a message whose media is one; present is zero for any other message */
    noshi_poll poll;
    char urls[NOSHI_MESSAGE_URLS_MAX];
    /* for a service message the new title, otherwise the message text; line breaks stay */
    char text[NOSHI_MESSAGE_TEXT_MAX];
} noshi_message_row;

typedef struct noshi_sticker_row {
    noshi_media_info media;
} noshi_sticker_row;

typedef struct noshi_sticker_set_row {
    int64_t id;
    int64_t access_hash;
    int32_t count;
    int32_t hash;
    int32_t thumb_dc;
    int32_t thumb_version;
    int64_t thumb_document_id;
    uint8_t official;
    uint8_t installed;      /* the account has the set among its own */
    char title[64];
    char short_name[48];
} noshi_sticker_set_row;

/* how a request names a chat: user and channel need the access hash, a basic group does not,
   and the chat with oneself is inputPeerSelf */
typedef struct noshi_peer_ref {
    int32_t kind;           /* 1 user, 2 chat, 3 channel, as noshi_peer */
    int64_t id;
    int64_t access_hash;
    uint8_t self;
    int32_t topic_id;       /* a forum topic the chat is narrowed to, zero for the whole chat */
} noshi_peer_ref;


/* one Document as a sticker; NOSHI_E_MALFORMED when it is not a sticker the app can show (a mask, a custom emoji,
   a document without the sticker attribute) */
noshi_status noshi_sticker_read(const noshi_tl_value *document, noshi_sticker_row *out);

/* a Message or MessageService; messageEmpty is NOSHI_E_NOTFOUND, anything else NOSHI_E_MALFORMED */
noshi_status noshi_message_read(const noshi_tl_value *message, noshi_message_row *out);

/* a messages.messages, messagesSlice or channelMessages answer in server order (newest first), at most cap rows */
noshi_status noshi_messages_parse(const noshi_tl_value *answer, noshi_message_row *rows, size_t cap, size_t *count);

/* the messages of an answer that did not read, deleted ones (messageEmpty) apart: how many, and the id and status of the first */
typedef struct noshi_messages_dropped {
    size_t count;
    int32_t first_id;
    noshi_status first_status;
} noshi_messages_dropped;

/* noshi_messages_parse that also tells what it left out; dropped may be NULL */
noshi_status noshi_messages_parse_counted(const noshi_tl_value *answer, noshi_message_row *rows, size_t cap, size_t *count, noshi_messages_dropped *dropped);

typedef struct noshi_history_page {
    uint32_t count;
    int32_t oldest_id;
    int32_t newest_id;
} noshi_history_page;

/* pagination follows server ids, including messageEmpty, not the locally visible or cached rows */
noshi_status noshi_history_page_read(const noshi_tl_value *answer, noshi_history_page *page);
noshi_status noshi_history_cursor_advance(int32_t previous, const noshi_history_page *page, uint32_t limit, int32_t *cursor, int *more);

/* a messages.allStickers answer; allStickersNotModified is NOSHI_E_NOTFOUND; sets of masks and of custom emoji
   are left out, they are no use in a message */
noshi_status noshi_sticker_sets_parse(const noshi_tl_value *answer, noshi_sticker_set_row *sets, size_t cap, size_t *count);

/* messages.getFeaturedStickers with hash zero, the trending sets */
noshi_status noshi_featured_stickers_request(noshi_arena *arena, noshi_tl_value **out);
noshi_status noshi_featured_stickers_parse(const noshi_tl_value *answer, noshi_sticker_set_row *sets, size_t cap, size_t *count);
/* messages.getArchivedStickers for sticker sets, a page of limit (1 to 100) after the set with offset_id, zero for
   the first page */
noshi_status noshi_archived_stickers_request(noshi_arena *arena, int64_t offset_id, int32_t limit, noshi_tl_value **out);
noshi_status noshi_archived_stickers_parse(const noshi_tl_value *answer, noshi_sticker_set_row *sets, size_t cap, size_t *count, int32_t *total);

/* a messages.stickerSet answer: the set header and its stickers in set order */
noshi_status noshi_sticker_set_parse(const noshi_tl_value *answer, noshi_sticker_set_row *set,
                                         noshi_sticker_row *stickers, size_t cap, size_t *count);
noshi_status noshi_animated_emoji_request(noshi_arena *arena, noshi_tl_value **out);
/* messages.getStickerSet of a set named by its short name, such as tg_placeholders_android; the name is 1 to 64
   letters, digits and underscores, else NOSHI_E_ARG */
noshi_status noshi_sticker_set_by_name_request(noshi_arena *arena, const char *short_name, noshi_tl_value **out);
/* official emoji pack mappings, with the pack emoticon in media.alt; unsupported formats are left out */
noshi_status noshi_animated_emoji_parse(const noshi_tl_value *answer, noshi_sticker_row *rows, size_t cap, size_t *count);

/* messages.getFavedStickers and messages.getSavedGifs with hash zero, which the server answers in full; read with the two parsers below */
noshi_status noshi_faved_stickers_request(noshi_arena *arena, noshi_tl_value **out);
noshi_status noshi_saved_gifs_request(noshi_arena *arena, noshi_tl_value **out);
/* a messages.favedStickers answer; favedStickersNotModified is NOSHI_E_NOTFOUND */
noshi_status noshi_faved_stickers_parse(const noshi_tl_value *answer, noshi_sticker_row *stickers, size_t cap, size_t *count);
/* a messages.savedGifs answer: the animations the account kept, as rows whose media kind is NOSHI_PREVIEW_GIF (a document that is no animation is
   left out); savedGifsNotModified is NOSHI_E_NOTFOUND */
noshi_status noshi_saved_gifs_parse(const noshi_tl_value *answer, noshi_sticker_row *gifs, size_t cap, size_t *count);
/* messages.faveSticker: puts the sticker among the favorites, or takes it out when unfave is set; the sticker is a document with its reference */
noshi_status noshi_fave_sticker_request(noshi_arena *arena, const noshi_media_ref *sticker, int unfave, noshi_tl_value **out);
/* messages.clearRecentStickers, which empties the recent list */
noshi_status noshi_clear_recent_stickers_request(noshi_arena *arena, noshi_tl_value **out);
/* a messages.recentStickers answer, newest first; recentStickersNotModified is NOSHI_E_NOTFOUND */
noshi_status noshi_recent_stickers_parse(const noshi_tl_value *answer, noshi_sticker_row *stickers, size_t cap, size_t *count);

/* the server id the answer to a send gave the message with this random id; NOSHI_E_NOTFOUND when it names none */
noshi_status noshi_sent_parse(const noshi_tl_value *updates, int64_t random_id, int32_t *id);

/* a message sent into a topic answers the topic root, which is how the server files it; General has no root to answer, and a chat
   without topics is left as it is */
noshi_status noshi_set_topic_reply(noshi_arena *arena, noshi_tl_value *request, const noshi_peer_ref *peer);

/* requests, all built in arena; a basic group or channel without its hash, or a user without one, is NOSHI_E_ARG */
noshi_status noshi_input_peer(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out);
/* messages.getPeerDialogs, at most 100 explicit peers per request */
noshi_status noshi_peer_dialogs_request(noshi_arena *arena, const noshi_peer_ref *peers, size_t count, noshi_tl_value **out);
noshi_status noshi_history_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t limit,
                                      noshi_tl_value **out);
/* the same with add_offset: a negative one moves the page toward newer messages, so offset_id of a message plus one with add_offset of minus half the limit gives the
   page around that message, and offset_id of the newest message held with minus the limit gives the page after it. add_offset must stay under the limit */
noshi_status noshi_history_window_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t add_offset, int32_t limit,
                                              noshi_tl_value **out);
/* messages.getSavedHistory: the messages of the favorites that came from one chat (the account itself for its own
   notes), newest first, read with noshi_messages_parse. source must be a user */
noshi_status noshi_saved_history_request(noshi_arena *arena, const noshi_peer_ref *source, int32_t offset_id, int32_t limit,
                                             noshi_tl_value **out);
/* the same with the negative add_offset of noshi_history_window_request */
noshi_status noshi_saved_history_window_request(noshi_arena *arena, const noshi_peer_ref *source, int32_t offset_id, int32_t add_offset, int32_t limit,
                                                    noshi_tl_value **out);
/* channels.exportMessageLink for one message of a channel or supergroup: the link, public or private, that opens
   it */
noshi_status noshi_message_link_request(noshi_arena *arena, const noshi_peer_ref *channel, int32_t id, noshi_tl_value **out);
/* the exportedMessageLink it answers: the address in link (capacity cap, at most 255 bytes kept) */
noshi_status noshi_message_link_parse(const noshi_tl_value *answer, char *link, size_t cap);
/* messages.search for the pinned messages of a chat or its topic, newest first, up to limit (1 to NOSHI_MESSAGES_MAX); the answer is read with
   noshi_messages_parse */
/* messages.getStickers for one emoji: the stickers the server suggests for it, as the empty chat's greeting asks
   with a waving hand */
#define NOSHI_STICKER_EMOTICON_MAX 32
noshi_status noshi_stickers_request(noshi_arena *arena, const char *emoticon, noshi_tl_value **out);
/* a messages.Stickers: NOSHI_E_NOTFOUND for stickersNotModified, which a request with hash zero never gets */
noshi_status noshi_stickers_parse(const noshi_tl_value *answer, noshi_sticker_row *stickers, size_t cap, size_t *count);
noshi_status noshi_pinned_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t limit, noshi_tl_value **out);
/* messages.getUnreadReactions for the messages of ours that got a reaction not seen yet, newest first, up to limit (1 to NOSHI_MESSAGES_MAX);
   read with noshi_messages_parse */
noshi_status noshi_unread_reactions_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t limit, noshi_tl_value **out);
/* messages.readReactions: every reaction of the chat or its topic counts as seen */
noshi_status noshi_read_reactions_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out);
/* messages.search for the messages that set a new photo of a group or channel, newest first, up to limit (1 to NOSHI_MESSAGES_MAX); the answer is
   read with noshi_chat_avatars_parse */
noshi_status noshi_chat_photos_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t limit, noshi_tl_value **out);
#define NOSHI_CHAT_SEARCH_QUERY_MAX 256
/* messages.search for a text in one chat, newest matches first, up to limit (1 to NOSHI_MESSAGES_MAX); read with
   the same parser as the pinned messages */
noshi_status noshi_chat_search_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *query, int32_t limit,
                                           noshi_tl_value **out);
/* messages.search for everything one person wrote in a chat, newest first, up to limit (1 to NOSHI_MESSAGES_MAX); read with the same parser.
   from must be a user with its hash, or the account itself (self set), anything else is NOSHI_E_ARG */
noshi_status noshi_chat_from_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_peer_ref *from, int32_t limit,
                                         noshi_tl_value **out);
/* messages.getMessages, or channels.getMessages for a channel, for these message ids (one to NOSHI_MESSAGES_MAX,
   all positive) */
noshi_status noshi_messages_by_id_request(noshi_arena *arena, const noshi_peer_ref *peer, const int32_t *ids, size_t count, noshi_tl_value **out);
/* sets schedule_date of a send request: the message waits on the server until that time (unix seconds, positive),
   and the account sees it in the scheduled messages of the chat */
noshi_status noshi_set_schedule(noshi_arena *arena, noshi_tl_value *request, int32_t date);
/* the kinds of media a chat is looked through by: its photos and videos, its files, its links */
typedef enum noshi_shared_kind {
    NOSHI_SHARED_MEDIA = 0,
    NOSHI_SHARED_FILES,
    NOSHI_SHARED_LINKS,
    NOSHI_SHARED_AUDIO,
    NOSHI_SHARED_VOICE
} noshi_shared_kind;
/* messages.search with the filter of a kind and no text, newest first, a page of limit (1 to NOSHI_MESSAGES_MAX) older than offset_id (zero for the
   newest); read with noshi_messages_parse */
noshi_status noshi_shared_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_shared_kind kind, int32_t offset_id, int32_t limit, noshi_tl_value **out);
/* messages.search for the messages the account itself wrote in a chat (from_id the account) or in one topic of it, newest first, a page of limit older than offset_id
   (zero for the newest); read with noshi_messages_parse */
noshi_status noshi_own_messages_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t offset_id, int32_t limit, noshi_tl_value **out);
/* the same search for the oldest limit messages of a kind (offset_id 1, add_offset -limit), still newest first inside the page */
noshi_status noshi_shared_oldest_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_shared_kind kind, int32_t limit, noshi_tl_value **out);

/* one photo or video of an album, once the server has it: what an inputMediaPhoto or inputMediaDocument needs */
#define NOSHI_ALBUM_ITEMS_MAX 10
#define NOSHI_ALBUM_REF_MAX 256
typedef struct noshi_album_media {
    uint8_t is_photo;               /* a photo, otherwise a document (a video) */
    int64_t id;
    int64_t access_hash;
    uint8_t file_reference[NOSHI_ALBUM_REF_MAX];
    size_t file_reference_len;
    uint8_t spoiler;                /* shown blurred until the person taps it */
} noshi_album_media;
struct noshi_upload_spec;
/* messages.uploadMedia for an uploaded file of this spec (a photo or a video) into the chat, which the server answers with the media to send */
noshi_status noshi_album_upload_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value *file, const struct noshi_upload_spec *spec,
                                            noshi_tl_value **out);
/* the messageMediaPhoto or messageMediaDocument it answers; out is always initialised and NOSHI_E_MALFORMED means anything else */
noshi_status noshi_album_media_parse(const noshi_tl_value *answer, noshi_album_media *out);
/* messages.sendMultiMedia of two to NOSHI_ALBUM_ITEMS_MAX items */
noshi_status noshi_album_send_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_album_media *items, const int64_t *random_ids,
                                          const char *const *captions, size_t count, noshi_tl_value **out);
/* the entity vector of text for a request that carries entities; *out stays NULL when none of them is sent. NOSHI_E_ARG for a range outside the text or
   a kind without what it points at */
noshi_status noshi_send_entities_build(noshi_arena *arena, const char *text, const noshi_send_entity *entities, size_t entity_count,
                                          noshi_tl_value **out);
/* every kind of entity but the ones the server finds itself (addresses, hashtags, commands) is sent; offsets and
   lengths count UTF-16 units of text */
noshi_status noshi_send_text_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *text,
                                        const noshi_send_entity *entities, size_t entity_count, int64_t random_id, noshi_tl_value **out);
/* the same as an answer to the message reply_to (zero for none, which is the plain request); a negative id is NOSHI_E_ARG */
noshi_status noshi_send_text_reply_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *text,
                                               const noshi_send_entity *entities, size_t entity_count, int64_t random_id, int32_t reply_to,
                                               noshi_tl_value **out);
/* sets reply_to of a send request: the message answered, with the topic when the chat has one; zero answers the topic root only */
noshi_status noshi_set_reply(noshi_arena *arena, noshi_tl_value *request, const noshi_peer_ref *peer, int32_t reply_to);
/* with the words of the answered message the reply is about; the offset is in UTF-16 units, negative when unknown */
noshi_status noshi_set_reply_quote(noshi_arena *arena, noshi_tl_value *request, const noshi_peer_ref *peer, int32_t reply_to,
                                       const char *quote, int32_t offset);
/* messages.sendMedia with inputMediaDice: the server throws the result and answers with the message; text must pass noshi_dice_emoticon and goes out as it was typed */
noshi_status noshi_send_dice_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *text, int64_t random_id, noshi_tl_value **out);
/* messages.getStickerSet of the set that animates one game emoji; the emoji must pass noshi_dice_emoticon */
noshi_status noshi_dice_set_request(noshi_arena *arena, const char *emoticon, noshi_tl_value **out);
/* the documents of that set in set order, one row each: the first is the animation that loops while the result is unknown and the one after it, at index value, is the throw that ends
   on that result. a document that is not a usable sticker keeps its place as a row with a source of none, so an index stays the value it stands for; slots have more than one
   animation per result and are read by the app from the same rows */
#define NOSHI_DICE_STICKERS_MAX 96
noshi_status noshi_dice_set_parse(const noshi_tl_value *answer, noshi_sticker_row *rows, size_t cap, size_t *count);
noshi_status noshi_send_sticker_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_media_ref *sticker,
                                           int64_t random_id, noshi_tl_value **out);
typedef enum noshi_upload_kind {
    NOSHI_UPLOAD_VOICE = 1,       /* an Ogg Opus voice note with its waveform */
    NOSHI_UPLOAD_ROUND,           /* a square mp4 played in a circle */
    NOSHI_UPLOAD_PHOTO,           /* a jpeg shown as a photo */
    NOSHI_UPLOAD_VIDEO,           /* an mp4 shown as a video */
    NOSHI_UPLOAD_FILE             /* anything else, sent as a document with its name */
} noshi_upload_kind;

/* the longest name a file system holds, 255 bytes, and the end of the string; the android client sends the name of the file as it is */
#define NOSHI_UPLOAD_NAME_MAX 256
/* a file system counts a name in characters (255 of them), and a name in Cyrillic or Chinese takes two or three bytes each, so a name a person gave a file can be longer than the buffer
   above. this writes it into out (capacity bytes with the end of the string) the way it is when it fits, and otherwise with the base of the name cut short at the edge of a character
   and the extension kept, so a long name goes out shortened and not as an error. NOSHI_E_ARG for a null pointer, a capacity under two, or a name with no room left for a character */
noshi_status noshi_upload_fit_name(const char *name, char *out, size_t capacity);
#define NOSHI_UPLOAD_CAPTION_MAX 4096
#define NOSHI_UPLOAD_MUSIC_TEXT_MAX 128

/* what a message about an uploaded file needs beyond the file itself */
typedef struct noshi_upload_spec {
    noshi_upload_kind kind;
    int32_t reply_to;
    int32_t duration_ms;
    int32_t width;                  /* a round video's side is the width */
    int32_t height;
    const uint8_t *waveform;
    size_t waveform_len;
    char caption[NOSHI_UPLOAD_CAPTION_MAX + 1];
    char name[NOSHI_UPLOAD_NAME_MAX];
    char mime[NOSHI_MEDIA_MIME_MAX];
    uint8_t spoiler;                /* a photo or a video that is shown blurred until it is tapped */
    uint8_t animated;               /* a file kind only: a gif that plays in the chat as an animation and not as a file to open */
    uint8_t view_once;              /* a photo, video, voice note or round video that is gone after the other side has opened it; files and albums cannot be */
    uint8_t music;                  /* a file kind only: the file is a song, sent with the title, performer and duration below and not forced to be a file */
    char title[NOSHI_UPLOAD_MUSIC_TEXT_MAX];
    char performer[NOSHI_UPLOAD_MUSIC_TEXT_MAX];
} noshi_upload_spec;

/* messages.sendMedia for a file already uploaded: file is the inputFile or inputFileBig the upload gave */
noshi_status noshi_send_upload_request(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value *file,
                                           const noshi_upload_spec *spec, int64_t random_id, noshi_tl_value **out);
/* messages.sendMedia with a point on the map; NOSHI_E_ARG outside the valid latitudes and longitudes */
noshi_status noshi_send_geo_request(noshi_arena *arena, const noshi_peer_ref *peer, double latitude, double longitude,
                                        int64_t random_id, noshi_tl_value **out);
noshi_status noshi_send_location_request(noshi_arena *arena, const noshi_peer_ref *peer, const noshi_geo_point *location,
                                            int64_t random_id, noshi_tl_value **out);
#define NOSHI_CUSTOM_EMOJI_MAX 100

/* a custom emoji by the document that draws it, and the ordinary emoji it stands for */
typedef struct noshi_custom_emoji {
    int64_t id;
    char alt[NOSHI_MEDIA_ALT_MAX];
    noshi_sticker_format format;  /* static webp, gzip lottie, or webm of which only the preview can be drawn */
    noshi_media_ref ref;          /* the file; source none when the document cannot be fetched */
    noshi_media_ref preview;      /* the thumbnail, the only picture of a webm emoji */
} noshi_custom_emoji;

/* one document of the server drawn as a small picture: its id, how it is stored, and the files to draw it from. alt is the text it stands for. a document that is
   empty or has no usable id is NOSHI_E_NOTFOUND and leaves out zeroed */
noshi_status noshi_document_picture_read(const noshi_tl_value *document, const char *alt, noshi_custom_emoji *out);
/* messages.getCustomEmojiDocuments for 1 to NOSHI_CUSTOM_EMOJI_MAX documents */
noshi_status noshi_custom_emoji_request(noshi_arena *arena, const int64_t *ids, size_t count, noshi_tl_value **out);
/* the answer to it: one row per document that carries the custom emoji attribute with a text, in answer order */
noshi_status noshi_custom_emoji_parse(const noshi_tl_value *answer, noshi_custom_emoji *rows, size_t cap, size_t *count);
/* messages.getEmojiStickers and its answer; only sets of custom emoji are kept, a set that is archived is left out */
noshi_status noshi_emoji_sets_request(noshi_arena *arena, noshi_tl_value **out);
noshi_status noshi_emoji_sets_parse(const noshi_tl_value *answer, noshi_sticker_set_row *sets, size_t cap, size_t *count);
/* a messages.stickerSet answer of a custom emoji set: the header and one row per emoji, in set order */
noshi_status noshi_emoji_set_parse(const noshi_tl_value *answer, noshi_sticker_set_row *set, noshi_custom_emoji *rows,
                                       size_t cap, size_t *count);
/* messages.searchGlobal for the text in every chat; kind narrows it to posts or to one kind of attachment. offset_rate is
   zero for the first page and next_rate of the previous one for the next */
noshi_status noshi_search_request(noshi_arena *arena, const char *query, noshi_search_kind kind, int32_t offset_rate,
                                      int32_t limit, noshi_tl_value **out);
/* messages.readHistory, channels.readHistory for a channel, or messages.readDiscussion for a peer narrowed to a topic */
int noshi_read_history_answer_valid(const noshi_peer_ref *peer, const noshi_tl_value *answer);
noshi_status noshi_read_history_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t max_id,
                                           noshi_tl_value **out);
/* the InputFileLocation of a ref, and of the thumbnail of a sticker set */
noshi_status noshi_media_location(noshi_arena *arena, const noshi_media_ref *ref, noshi_tl_value **out);
noshi_status noshi_sticker_set_thumb_location(noshi_arena *arena, const noshi_sticker_set_row *set, noshi_tl_value **out);
noshi_status noshi_sticker_set_request(noshi_arena *arena, const noshi_sticker_set_row *set, noshi_tl_value **out);

#endif

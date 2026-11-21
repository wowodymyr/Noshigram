#ifndef NOSHI_BOTS_H
#define NOSHI_BOTS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_dialogs.h"
#include "noshi_markup.h"
#include "noshi_media.h"
#include "noshi_messages.h"
#include "noshi_people.h"
#include "noshi_tl.h"

/* a bot is a user: it is named in requests by an noshi_peer_ref of kind 1 with its access hash, a chat by the
   same */

/* a start parameter: up to 64 characters of A-Z a-z 0-9 _ - as the server takes them */
#define NOSHI_START_PARAM_MAX 64
/* the shape of a public name, without the @ */
#define NOSHI_USERNAME_LOOKUP_MAX 32

/* resolving a public name */
typedef struct noshi_resolved {
    noshi_dialog_row dialog;      /* the peer as a chat: kind, title, photo and access hash */
    uint8_t is_user;
    noshi_person_row person;      /* the user itself, with the flags of a bot */
} noshi_resolved;

/* contacts.resolveUsername; a name with a character outside A-Z a-z 0-9 _, or not 1 to 32 long, is NOSHI_E_ARG */
noshi_status noshi_resolve_request(noshi_arena *arena, const char *username, noshi_tl_value **out);
/* the contacts.resolvedPeer answer */
noshi_status noshi_resolve_parse(const noshi_tl_value *answer, int64_t self_id, noshi_resolved *out);

/* the inline bots the account used most lately */
#define NOSHI_TOP_BOTS_MAX 20
/* contacts.getTopPeers for the inline bots only, at most limit of them (1 to NOSHI_TOP_BOTS_MAX) */
noshi_status noshi_top_inline_bots_request(noshi_arena *arena, int32_t limit, noshi_tl_value **out);
/* the bots of a contacts.topPeers answer, the most used first: only users that are bots and have a public name, since a mention is that name. A disabled or unchanged answer
   holds none and is not an error; anything else that is not a topPeers answer is NOSHI_E_MALFORMED */
noshi_status noshi_top_inline_bots_parse(const noshi_tl_value *answer, noshi_person_row *rows, size_t cap, size_t *count);

/* an invite link to a private group or channel */
#define NOSHI_INVITE_ABOUT_MAX 512
typedef struct noshi_invite {
    uint8_t member;                 /* the account is in the chat already (or may peek at it): dialog is set and about is not */
    noshi_dialog_row dialog;
    char title[NOSHI_DIALOG_TITLE_MAX];
    char about[NOSHI_INVITE_ABOUT_MAX];
    noshi_media_ref photo;
    int32_t participants;
    uint8_t broadcast;              /* a channel, not a group */
    uint8_t request_needed;         /* joining sends a request that an admin approves */
    uint8_t verified;
    int64_t subscription_stars;     /* a paid channel: the stars each period costs, zero for a free chat */
    int32_t subscription_period;    /* the length of that period in seconds */
} noshi_invite;

/* messages.checkChatInvite and messages.importChatInvite; a hash outside A-Z a-z 0-9 _ - or longer than 128 is NOSHI_E_ARG */
noshi_status noshi_invite_check_request(noshi_arena *arena, const char *hash, noshi_tl_value **out);
noshi_status noshi_invite_import_request(noshi_arena *arena, const char *hash, noshi_tl_value **out);
/* the invoice that pays the subscription a paid invite asks for; the hash is checked as for the requests above */
noshi_status noshi_invite_subscription_invoice(noshi_arena *arena, const char *hash, noshi_tl_value **out);
/* the ChatInvite answer */
noshi_status noshi_invite_parse(const noshi_tl_value *answer, int64_t self_id, noshi_invite *out);
/* the answer of the import: the chat the account joined, from the chats of the updates; a bot check that needs a web view is
   NOSHI_E_UNSUPPORTED */
noshi_status noshi_invite_joined_parse(const noshi_tl_value *answer, int64_t self_id, noshi_dialog_row *out);

/* what a bot says about itself in the chat that has no messages yet, and its menu */
#define NOSHI_BOT_COMMANDS_MAX 100
#define NOSHI_BOT_COMMAND_MAX 40
#define NOSHI_BOT_COMMAND_TEXT_MAX 132
#define NOSHI_BOT_DESCRIPTION_MAX 2048
#define NOSHI_BOT_MENU_TEXT_MAX 48
#define NOSHI_BOT_URL_MAX 1024

typedef struct noshi_bot_command {
    char name[NOSHI_BOT_COMMAND_MAX];     /* without the slash */
    char text[NOSHI_BOT_COMMAND_TEXT_MAX];
} noshi_bot_command;

typedef enum noshi_bot_menu_kind {
    NOSHI_BOT_MENU_DEFAULT = 0,
    NOSHI_BOT_MENU_COMMANDS       /* the list of commands */
} noshi_bot_menu_kind;

typedef struct noshi_bot_info {
    uint8_t present;                /* the user carries bot info at all */
    char description[NOSHI_BOT_DESCRIPTION_MAX];
    uint8_t has_picture;
    noshi_media_info picture;     /* the picture or animation shown above the description */
    uint8_t menu_kind;              /* noshi_bot_menu_kind */
    char privacy_url[NOSHI_BOT_URL_MAX];
    uint16_t command_count;
    noshi_bot_command commands[NOSHI_BOT_COMMANDS_MAX];
} noshi_bot_info;

/* the bot info of a users.userFull answer; a user that is not a bot leaves present zero. out is always initialised */
noshi_status noshi_bot_info_parse(const noshi_tl_value *answer, noshi_bot_info *out);

/* contacts.addContact for a user the person already knows or finds: it stores the name the person gives, which is
   the one shown instead of the name the user chose */
#define NOSHI_CONTACT_NAME_MAX 64
noshi_status noshi_contact_edit_request(noshi_arena *arena, const noshi_peer_ref *user, const char *first, const char *last, const char *phone,
                                            noshi_tl_value **out);
/* contacts.importContacts for one phone number: the way to add someone who is not known yet */
noshi_status noshi_contact_import_request(noshi_arena *arena, const char *phone, const char *first, const char *last, noshi_tl_value **out);
/* how many of the numbers the server found an account for in a contacts.importedContacts answer; anything else is NOSHI_E_MALFORMED */
noshi_status noshi_contact_import_parse(const noshi_tl_value *answer, size_t *imported);
/* messages.startBot: the first message of a chat with a bot. random_id is not zero */
noshi_status noshi_start_bot_request(noshi_arena *arena, const noshi_peer_ref *bot, const noshi_peer_ref *peer,
                                         int64_t random_id, const char *param, noshi_tl_value **out);

/* the press of a callback button */
#define NOSHI_CALLBACK_TEXT_MAX 1024
#define NOSHI_CALLBACK_URL_MAX 1024

typedef struct noshi_callback_answer {
    uint8_t alert;                  /* shown as a dialog instead of a short note */
    uint8_t has_url;
    uint8_t native_ui;
    int32_t cache_time;
    char message[NOSHI_CALLBACK_TEXT_MAX];
    char url[NOSHI_CALLBACK_URL_MAX];
} noshi_callback_answer;

/* messages.getBotCallbackAnswer for the button with data (at most 64 bytes) on a message */
noshi_status noshi_callback_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, const uint8_t *data,
                                        size_t data_len, int game, noshi_tl_value *password, noshi_tl_value **out);
noshi_status noshi_callback_parse(const noshi_tl_value *answer, noshi_callback_answer *out);

/* the inputCheckPasswordSRP for a password, from the account.password answer of account.getPassword;
   NOSHI_E_UNSUPPORTED when the account has no password or uses a scheme this client cannot compute */
noshi_status noshi_password_input(noshi_arena *arena, const noshi_tl_value *account_password, const char *password,
                                      noshi_tl_value **out);
noshi_status noshi_password_request(noshi_arena *arena, noshi_tl_value **out);

/* inline mode: @bot query in any chat */
#define NOSHI_INLINE_ID_MAX 72
#define NOSHI_INLINE_TITLE_MAX 100
#define NOSHI_INLINE_TEXT_MAX 200
#define NOSHI_INLINE_OFFSET_MAX 80
#define NOSHI_INLINE_RESULTS_MAX 50

/* parses the leading @name and returns the query inside text */
int noshi_inline_address_parse(const char *text, char *name, size_t capacity, const char **query);
#define NOSHI_INLINE_QUERY_MAX 256
#define NOSHI_WEB_URL_MAX 512

typedef enum noshi_inline_kind {
    NOSHI_INLINE_OTHER = 0,
    NOSHI_INLINE_ARTICLE,
    NOSHI_INLINE_PHOTO,
    NOSHI_INLINE_GIF,
    NOSHI_INLINE_VIDEO,
    NOSHI_INLINE_AUDIO,
    NOSHI_INLINE_VOICE,
    NOSHI_INLINE_FILE,
    NOSHI_INLINE_STICKER,
    NOSHI_INLINE_LOCATION,
    NOSHI_INLINE_CONTACT,
    NOSHI_INLINE_GAME
} noshi_inline_kind;

/* a picture a bot hosts itself: fetched by address, through the servers when the bot asked for a proxy */
typedef struct noshi_web_ref {
    uint8_t present;
    uint8_t proxied;                /* upload.getWebFile with the access hash, otherwise a plain GET of url */
    int64_t access_hash;
    int32_t size;
    char url[NOSHI_WEB_URL_MAX];
    char mime[NOSHI_MEDIA_MIME_MAX];
} noshi_web_ref;

typedef struct noshi_inline_result {
    uint8_t kind;                   /* noshi_inline_kind */
    int64_t query_id;               /* the page that produced this result */
    char id[NOSHI_INLINE_ID_MAX];
    char title[NOSHI_INLINE_TITLE_MAX];
    char description[NOSHI_INLINE_TEXT_MAX];
    noshi_media_info media;       /* the photo or document the server holds; kind text without one */
    noshi_web_ref thumb;          /* the picture the bot hosts */
    int32_t width;
    int32_t height;
    int32_t duration;
} noshi_inline_result;

typedef struct noshi_inline_page {
    int64_t query_id;
    uint8_t gallery;                /* the results are pictures, shown as a grid */
    int32_t cache_time;
    char next_offset[NOSHI_INLINE_OFFSET_MAX];    /* empty on the last page */
    char switch_text[NOSHI_BOT_MENU_TEXT_MAX];    /* a button that opens the chat with the bot */
    char switch_param[NOSHI_START_PARAM_MAX + 1];
    char web_text[NOSHI_BOT_MENU_TEXT_MAX];
} noshi_inline_page;

/* messages.getInlineBotResults; offset is "" for the first page */
noshi_status noshi_inline_query_request(noshi_arena *arena, const noshi_peer_ref *bot, const noshi_peer_ref *peer,
                                            const char *query, const char *offset, noshi_tl_value **out);
noshi_status noshi_inline_query_set_location(noshi_arena *arena, noshi_tl_value *request, const noshi_geo_point *point);
/* a messages.botResults answer into page and at most cap results; a result this client cannot show is skipped */
noshi_status noshi_inline_results_parse(const noshi_tl_value *answer, noshi_inline_page *page, noshi_inline_result *rows,
                                            size_t cap, size_t *count);
/* messages.sendInlineBotResult of the result with id from the page with query_id */
noshi_status noshi_inline_send_request(noshi_arena *arena, const noshi_peer_ref *peer, int64_t random_id, int64_t query_id,
                                           const char *result_id, noshi_tl_value **out);

/* users.getUsers for a user named by a message that mentions them, which is how a button or a text mention gives the access hash that
   opening their profile needs. peer and msg_id name the message */
noshi_status noshi_user_from_message_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, int64_t user_id, noshi_tl_value **out);
/* the user with user_id in the answer to it; NOSHI_E_NOTFOUND when the answer does not carry that user */
noshi_status noshi_user_from_message_parse(const noshi_tl_value *answer, int64_t user_id, noshi_person_row *out);

/* a link in a message or a button that asks to sign the person in on the bot's site */
#define NOSHI_URL_AUTH_CODES_MAX 8
#define NOSHI_URL_AUTH_NAME_MAX 96

typedef enum noshi_url_auth_kind {
    NOSHI_URL_AUTH_OPEN = 0,      /* nothing to ask: open the address as it is */
    NOSHI_URL_AUTH_ASK,           /* the person decides whether to sign in */
    NOSHI_URL_AUTH_DONE           /* signed in; url is the address to open */
} noshi_url_auth_kind;

typedef struct noshi_url_auth {
    uint8_t kind;                   /* noshi_url_auth_kind */
    uint8_t request_write;          /* the site asks to message the person */
    uint8_t request_phone;          /* the site asks for the phone number */
    uint8_t code_count;             /* the person must pick the code the site shows from these */
    char bot[NOSHI_URL_AUTH_NAME_MAX];
    char domain[NOSHI_URL_AUTH_NAME_MAX];
    char url[NOSHI_BOT_URL_MAX];
    char codes[NOSHI_URL_AUTH_CODES_MAX][16];
} noshi_url_auth;

/* messages.requestUrlAuth for a button (peer, msg_id, button_id) or, with peer NULL, for a bare address */
noshi_status noshi_url_auth_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, int32_t button_id,
                                        const char *url, noshi_tl_value **out);
noshi_status noshi_url_auth_parse(const noshi_tl_value *answer, noshi_url_auth *out);
/* messages.acceptUrlAuth; code is the chosen one of the codes, or NULL */
noshi_status noshi_url_auth_accept_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, int32_t button_id,
                                               const char *url, int write_allowed, int share_phone, const char *code, noshi_tl_value **out);

/* an invoice paid in stars */
typedef struct noshi_stars_form {
    int64_t form_id;
    int64_t bot_id;
    int64_t stars;
    char title[NOSHI_INLINE_TITLE_MAX];
    char description[NOSHI_INLINE_TEXT_MAX * 2];
} noshi_stars_form;

/* inputInvoiceMessage for the invoice of a message, and inputInvoiceSlug for one a link names by its slug (letters, digits, _ and -) */
noshi_status noshi_invoice_message_input(noshi_arena *arena, const noshi_peer_ref *peer, int32_t msg_id, noshi_tl_value **out);
noshi_status noshi_invoice_slug_input(noshi_arena *arena, const char *slug, noshi_tl_value **out);
/* a payments.paymentFormStars answer */
noshi_status noshi_stars_form_parse(const noshi_tl_value *answer, noshi_stars_form *out);

/* answers a bot's keyboard */
/* messages.sendMedia with the person's own number, for a button that asks for it */
noshi_status noshi_send_contact_request(noshi_arena *arena, const noshi_peer_ref *peer, const char *phone, const char *first_name,
                                            const char *last_name, int64_t random_id, noshi_tl_value **out);
/* messages.sendBotRequestedPeer: the chats the person picked for a request peer button of the message msg_id */
noshi_status noshi_requested_peers_request(noshi_arena *arena, const noshi_peer_ref *bot_chat, int32_t msg_id, int32_t button_id,
                                               const noshi_peer_ref *peers, size_t count, noshi_tl_value **out);

#endif

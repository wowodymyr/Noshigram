#ifndef NOSHI_MARKUP_H
#define NOSHI_MARKUP_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_tl.h"
#include "noshi_welcome.h"

/* the server takes 100 buttons in a keyboard; a bigger one is cut there so a hostile answer cannot grow the rows */
#define NOSHI_MARKUP_ROWS_MAX 40
#define NOSHI_MARKUP_ROW_MAX 12
#define NOSHI_MARKUP_BUTTONS_MAX 100
#define NOSHI_MARKUP_TEXT_MAX 96
#define NOSHI_MARKUP_DATA_MAX 64
#define NOSHI_MARKUP_POOL_MAX 8192
#define NOSHI_MARKUP_PLACEHOLDER_MAX 96

typedef enum noshi_markup_kind {
    NOSHI_MARKUP_NONE = 0,
    NOSHI_MARKUP_INLINE,          /* buttons under the message */
    NOSHI_MARKUP_KEYBOARD,        /* replaces the keyboard of the chat */
    NOSHI_MARKUP_HIDE,            /* takes a reply keyboard away */
    NOSHI_MARKUP_FORCE_REPLY      /* asks for an answer to the message */
} noshi_markup_kind;

typedef enum noshi_button_kind {
    NOSHI_BUTTON_TEXT = 1,        /* a reply keyboard button: sends its own text */
    NOSHI_BUTTON_URL,
    NOSHI_BUTTON_CALLBACK,
    NOSHI_BUTTON_URL_AUTH,        /* a link that signs the person in on the bot's site */
    NOSHI_BUTTON_SWITCH_INLINE,
    NOSHI_BUTTON_GAME,
    NOSHI_BUTTON_BUY,
    NOSHI_BUTTON_COPY,
    NOSHI_BUTTON_USER_PROFILE,
    NOSHI_BUTTON_REQUEST_PHONE,
    NOSHI_BUTTON_REQUEST_GEO,
    NOSHI_BUTTON_REQUEST_POLL,
    NOSHI_BUTTON_REQUEST_PEER,
    NOSHI_BUTTON_DISABLED         /* a kind this client does not know (a web app button among them), or one that does not fit; shown, never acted on */
} noshi_button_kind;

typedef enum noshi_button_style {
    NOSHI_BUTTON_STYLE_PLAIN = 0,
    NOSHI_BUTTON_STYLE_PRIMARY,
    NOSHI_BUTTON_STYLE_DANGER,
    NOSHI_BUTTON_STYLE_SUCCESS
} noshi_button_style;

/* what kind of chat a request peer button asks the person to choose */
typedef enum noshi_peer_choice {
    NOSHI_CHOICE_USER = 1,
    NOSHI_CHOICE_GROUP,
    NOSHI_CHOICE_CHANNEL,
    NOSHI_CHOICE_CREATE_BOT       /* a new bot, which this client cannot make */
} noshi_peer_choice;

/* a condition of a request peer button: the chat may be anything, must have the property, or must not */
enum { NOSHI_WANT_ANY = 0, NOSHI_WANT_YES = 1, NOSHI_WANT_NO = 2 };

typedef struct noshi_markup_button {
    uint8_t kind;               /* noshi_button_kind */
    uint8_t style;              /* noshi_button_style */
    uint8_t password;           /* callback: the server wants the 2fa password with the press */
    uint8_t same_peer;          /* switch inline: only in the chat the message is in */
    uint8_t quiz;               /* request poll: NOSHI_WANT_YES for a quiz only, NOSHI_WANT_NO for a plain poll only */
    uint8_t data_len;           /* callback payload bytes in data */
    uint8_t choice;             /* request peer: noshi_peer_choice */
    uint8_t want_bot;           /* request peer, users: bots only or people only */
    uint8_t want_premium;
    uint8_t want_username;      /* request peer, chats and channels */
    uint8_t want_forum;
    uint8_t want_creator;       /* request peer: chats the person owns */
    uint8_t max_quantity;       /* request peer: how many the person may pick, at least 1 */
    int32_t button_id;          /* url auth and request peer: names the button to the server */
    int64_t user_id;            /* user profile */
    int64_t icon;               /* the custom emoji that decorates the button, zero for none */
    uint16_t arg_offset;        /* into the pool: the address, the inline query, the text to copy */
    uint16_t arg_length;
    char text[NOSHI_MARKUP_TEXT_MAX];
    uint8_t data[NOSHI_MARKUP_DATA_MAX];
} noshi_markup_button;

typedef struct noshi_markup {
    uint8_t kind;               /* noshi_markup_kind */
    uint8_t resize;             /* keyboard: only as tall as its rows need */
    uint8_t single_use;         /* keyboard: goes away after one press */
    uint8_t persistent;         /* keyboard: stays open when the person types */
    uint8_t selective;          /* meant for some of the people in the chat only */
    uint8_t row_count;
    uint8_t row_size[NOSHI_MARKUP_ROWS_MAX];
    uint16_t button_count;
    uint16_t pool_len;
    char placeholder[NOSHI_MARKUP_PLACEHOLDER_MAX];
    noshi_markup_button buttons[NOSHI_MARKUP_BUTTONS_MAX];
    char pool[NOSHI_MARKUP_POOL_MAX];
} noshi_markup;

/* a ReplyMarkup, or NULL for a message that has none. out is always initialised and left as kind none when there
   is nothing to show */
noshi_status noshi_markup_read(const noshi_tl_value *markup, noshi_markup *out);

/* the text of a button argument (address, query, text to copy), terminated; an empty string for a button that has none */
const char *noshi_markup_arg(const noshi_markup *markup, const noshi_markup_button *button);

/* the frames of the buttons in reading order for a width */
noshi_status noshi_markup_layout(const uint8_t *row_size, size_t row_count, double width, double row_height, double gap,
                                     noshi_rect *frames, size_t cap, double *height);

#endif

#ifndef NOSHI_LINKS_H
#define NOSHI_LINKS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"

#define NOSHI_LINK_URL_MAX 2048
/* the longest code of a language pack the links accept, such as "pt-br" or "classic-zh-cn" */
#define NOSHI_LINK_LANGUAGE_MAX 32
#define NOSHI_LINK_NAME_MAX 33
#define NOSHI_LINK_PARAM_MAX 65
#define NOSHI_LINK_SLUG_MAX 129
#define NOSHI_LINK_SERVER_MAX 256
#define NOSHI_LINK_SECRET_MAX 275
#define NOSHI_LINK_CREDENTIAL_MAX 65

typedef enum noshi_link_kind {
    NOSHI_LINK_OTHER = 0,     /* not a telegram link this client acts on: open it as an ordinary address */
    NOSHI_LINK_PEER,          /* a user, bot, group or channel by its name, with what the link asks of it */
    NOSHI_LINK_INVOICE,       /* an invoice by its slug */
    NOSHI_LINK_PROXY,         /* an MTProto proxy: server, port and secret */
    NOSHI_LINK_SOCKS,         /* a SOCKS5 proxy: server and port, with a user and a password or without */
    NOSHI_LINK_INVITE,        /* an invite to a private group or channel: the hash is in slug */
    NOSHI_LINK_CALL,          /* t.me/call/<slug>: a conference call by its slug */
    NOSHI_LINK_PRIVATE_POST,  /* t.me/c/<channel>/<post> or tg://privatepost: a message of a channel or group by its number, for members */
    NOSHI_LINK_LANGUAGE,      /* t.me/setlanguage/<code> or tg://setlanguage?lang=<code>: a language pack by its code, which is in slug */
    NOSHI_LINK_THEME          /* t.me/addtheme/<slug> or tg://addtheme?slug=<slug>: a cloud theme by its slug */
} noshi_link_kind;

typedef struct noshi_tg_link {
    noshi_link_kind kind;
    char username[NOSHI_LINK_NAME_MAX];
    uint8_t has_start;              /* ?start= was given, also when it is empty */
    char start[NOSHI_LINK_PARAM_MAX];
    char app_name[NOSHI_LINK_NAME_MAX];   /* t.me/bot/app: the short name of one of the bot's apps */
    uint8_t has_start_app;          /* ?startapp=, which opens the bot's main app when no app name is given */
    char start_app[NOSHI_LINK_PARAM_MAX];
    int32_t message_id;             /* t.me/name/123, zero without one */
    int64_t channel_id;             /* the number of the channel or group of a private post link, as it stands in the link (without the -100) */
    /* ?videochat= or ?voicechat= on a name: the voice chat of that group or channel, joined with this invite hash (empty when the parameter has no value) */
    uint8_t has_voice_chat;
    char voice_chat[NOSHI_LINK_PARAM_MAX];
    char slug[NOSHI_LINK_SLUG_MAX];
    /* the proxy links: the secret stays as typed in the link (hex or base64url), for noshi_proxy_secret_decode */
    char proxy_server[NOSHI_LINK_SERVER_MAX];
    uint16_t proxy_port;
    char proxy_secret[NOSHI_LINK_SECRET_MAX];
    char proxy_user[NOSHI_LINK_CREDENTIAL_MAX];
    char proxy_password[NOSHI_LINK_CREDENTIAL_MAX];
} noshi_tg_link;

/* reads tg:// links and the t.me, telegram.me and telegram.dog forms of them; anything else is kind other with
   NOSHI_OK */
noshi_status noshi_tg_link_parse(const char *url, noshi_tg_link *out);

/* the name of a mention ("@name" or "name") when it has the shape of a public name; NOSHI_E_MALFORMED otherwise */
noshi_status noshi_mention_name(const char *text, char *out, size_t cap);

/* a bot command as it stands in a message: "/start", "/start@helper_bot". command gets the part before the @ with
   the slash, bot the name after it (empty without one) */
noshi_status noshi_bot_command_split(const char *text, char *command, size_t command_cap, char *bot, size_t bot_cap);

#endif

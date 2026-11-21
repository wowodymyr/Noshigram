#ifndef NOSHI_PEOPLE_H
#define NOSHI_PEOPLE_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_photos.h"
#include "noshi_tl.h"

#define NOSHI_PEOPLE_MAX 2000
/* telegram delivers service notifications in this account's chat */
#define NOSHI_TELEGRAM_SERVICE_USER_ID 777000LL
#define NOSHI_PERSON_NAME_MAX 128
#define NOSHI_PERSON_USERNAME_MAX 64
#define NOSHI_PERSON_PHONE_MAX 32

typedef enum noshi_presence {
    NOSHI_PRESENCE_UNKNOWN = 0,
    NOSHI_PRESENCE_ONLINE,
    NOSHI_PRESENCE_OFFLINE,   /* seen is the unix time it went offline */
    NOSHI_PRESENCE_RECENTLY,
    NOSHI_PRESENCE_LAST_WEEK,
    NOSHI_PRESENCE_LAST_MONTH,
    NOSHI_PRESENCE_DELETED   /* the account is gone; the server sends no status for it, and the UI says so apart from a hidden one */
} noshi_presence;

typedef struct noshi_person_row {
    int64_t id;
    int64_t access_hash;    /* what an input peer needs; zero when the object came from a mention and carries none */
    uint8_t bot;
    uint8_t bot_inline;     /* a bot that answers @name queries in any chat */
    uint8_t bot_inline_geo; /* and asks for the location with them */
    uint8_t bot_no_chats;   /* a bot that cannot be added to groups */
    uint8_t bot_reads_all;  /* a bot that sees every message of a group, not only the commands */
    uint8_t verified;
    uint8_t contact;        /* in the contacts of the account */
    uint8_t mutual;         /* and the account is in the contacts of this user too */
    uint8_t premium;        /* Telegram Premium: may write custom emoji */
    int64_t emoji_status;       /* the custom emoji document shown after the name, zero without one */
    int32_t emoji_status_until; /* unix time the status ends, zero when it has no end */
    int64_t emoji_status_collectible; /* the id of the unique gift worn as the status, zero when the status is no gift */
    uint8_t deleted;
    uint8_t has_name_color;     /* the user chose the color of the name in group chats (a PeerColor with a color id) */
    int32_t name_color;         /* its id, 0 to 6 free for everyone and above them for Premium accounts */
    /* the backdrop of the profile, from a collectible profile color or else a collectible emoji status: the radial colors as 0xRRGGBB, the color of the
       tiles and of the text over it, and the emoji that tiles it */
    uint8_t has_profile_color;  /* the user chose a profile color from the server's list (a plain PeerColor on profile_color) */
    int32_t profile_color_id;
    int64_t profile_color_emoji;    /* the emoji that tiles it, zero without one */
    uint8_t has_backdrop;
    uint32_t backdrop_center;
    uint32_t backdrop_edge;
    uint32_t backdrop_pattern;
    uint32_t backdrop_text;
    int64_t backdrop_pattern_document;  /* zero without one */
    char backdrop_title[NOSHI_PERSON_NAME_MAX];   /* the name of the collectible and its number ("Cookie Heart #5916"), empty without one */
    noshi_presence presence;
    int32_t seen;
    noshi_photo_ref photo;
    char name[NOSHI_PERSON_NAME_MAX];
    char username[NOSHI_PERSON_USERNAME_MAX];
    char phone[NOSHI_PERSON_PHONE_MAX];
    char bot_placeholder[NOSHI_PERSON_NAME_MAX];  /* the hint the field shows after @name; empty without one */
} noshi_person_row;

/* a UserStatus: online, offline with the time it left, or one of the coarse "recently" ranges; anything else, a
   missing status or one the user hid from us, is unknown */
void noshi_presence_read(const noshi_tl_value *status, noshi_presence *presence, int32_t *seen);

/* the custom emoji a user shows after their name; the caller compares until with the clock, which keeps the parse
   deterministic */
void noshi_emoji_status_read(const noshi_tl_value *user, int64_t *document, int32_t *until);
/* the id of the unique gift that is the emoji status of the user (an emojiStatusCollectible), zero for any other status or none */
int64_t noshi_emoji_status_collectible(const noshi_tl_value *user);

/* a User object: a userEmpty or a user without an id is NOSHI_E_MALFORMED */
noshi_status noshi_person_parse(const noshi_tl_value *user, noshi_person_row *out);

/* a channel or community sender, including forbidden objects that still carry a title */
noshi_status noshi_channel_person_parse(const noshi_tl_value *channel, noshi_person_row *out);

/* the backgrounds of the profile colors the server lists, by the id a user's profile_color names */
#define NOSHI_PROFILE_COLORS_MAX 64
typedef struct noshi_profile_color {
    int32_t id;
    uint32_t bg[2];         /* the two ends of the blend as 0xRRGGBB; a single color is both */
    uint32_t dark_bg[2];    /* the same for the dark theme, valid when has_dark is set */
    uint8_t has_dark;
} noshi_profile_color;

/* help.getPeerProfileColors; hash is the one of the last answer, zero for the first */
noshi_status noshi_profile_colors_request(noshi_arena *arena, int32_t hash, noshi_tl_value **out);
/* a help.peerColors answer in server order, at most cap rows; options without colors are left out. help.peerColorsNotModified is NOSHI_E_NOTFOUND */
noshi_status noshi_profile_colors_parse(const noshi_tl_value *answer, noshi_profile_color *rows, size_t cap, size_t *count, int32_t *hash);

#define NOSHI_GROUP_ROLES_MAX 200
typedef struct noshi_group_role {
    int64_t user_id;
    uint8_t owner;
    uint8_t admin;
    char rank[NOSHI_PERSON_NAME_MAX];
} noshi_group_role;

noshi_status noshi_group_roles_request(noshi_arena *arena, int32_t kind, int64_t id, int64_t hash, noshi_tl_value **out);
/* the admins of a supergroup, or the participants of a basic group, including custom ranks */
noshi_status noshi_group_roles_parse(const noshi_tl_value *answer, int64_t id, noshi_group_role *rows, size_t cap, size_t *count);

/* a contacts.contacts answer, in server order, at most cap rows */
noshi_status noshi_contacts_parse(const noshi_tl_value *answer, noshi_person_row *rows, size_t cap, size_t *count);

#endif

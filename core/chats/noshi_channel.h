#ifndef NOSHI_CHANNEL_H
#define NOSHI_CHANNEL_H

#include <stdint.h>

#include "noshi_dialogs.h"
#include "noshi_people.h"
#include "noshi_messages.h"
#include "noshi_profile.h"
#include "noshi_tl.h"

#define NOSHI_CHANNEL_USERNAME_MAX 64
#define NOSHI_CHANNEL_LINK_MAX 128
#define NOSHI_CHANNEL_TITLE_MAX 128
#define NOSHI_MEMBERS_PAGE 50
#define NOSHI_MEMBERS_MAX 100
#define NOSHI_MEMBER_RANK_MAX 64
#define NOSHI_MEMBERS_QUERY_MAX 64

/* the rights of an administrator, one bit each, in the order the editor lists them */
#define NOSHI_ADMIN_CHANGE_INFO     0x001u
#define NOSHI_ADMIN_POST_MESSAGES   0x002u
#define NOSHI_ADMIN_EDIT_MESSAGES   0x004u
#define NOSHI_ADMIN_DELETE_MESSAGES 0x008u
#define NOSHI_ADMIN_BAN_USERS       0x010u
#define NOSHI_ADMIN_INVITE_USERS    0x020u
#define NOSHI_ADMIN_PIN_MESSAGES    0x040u
#define NOSHI_ADMIN_ADD_ADMINS      0x080u
#define NOSHI_ADMIN_MANAGE_CALL     0x100u
#define NOSHI_ADMIN_ANONYMOUS       0x200u
#define NOSHI_ADMIN_MANAGE_TOPICS   0x400u
#define NOSHI_ADMIN_ALL             0x7FFu

/* the background an admin gave a channel: a gradient of one to four colors, with a pattern over it or a picture in its place */
typedef struct noshi_chat_wallpaper {
    uint8_t present;                /* zero when the channel has none, and every other field is then zero too */
    uint8_t pattern;                /* the file is a pattern drawn over the colors, not a picture */
    uint8_t blur;
    uint8_t color_count;            /* 0 to 4 of colors */
    uint32_t colors[4];             /* 0xRRGGBB */
    int32_t rotation;               /* degrees of the gradient, as the server sends them */
    int32_t intensity;              /* 0 to 100, how strong the pattern is; the sign the server gives a dark pattern is dropped */
    uint8_t has_file;
    noshi_media_ref file;
    int64_t file_size;
} noshi_chat_wallpaper;

/* a wallPaper or wallPaperNoFile; anything else is none. out is always initialised */
void noshi_chat_wallpaper_read(const noshi_tl_value *wallpaper, noshi_chat_wallpaper *out);

/* what the profile of a channel shows, read from a channels.getFullChannel answer */
typedef struct noshi_full_channel {
    noshi_dialog_row dialog;      /* the channel as a chat: title, picture, access hash */
    uint8_t megagroup;              /* a group built on a channel, as opposed to a broadcast channel */
    uint8_t membership_known;       /* a min channel does not carry the account's membership */
    uint8_t verified;
    uint8_t muted;                  /* notifications are off now */
    uint8_t can_view_stats;
    uint8_t gifts_available;        /* the channel takes gifts */
    uint8_t creator;                /* the account made the channel, so it holds every right */
    uint8_t signatures;             /* posts carry the name of the admin who wrote them */
    uint8_t basic;                  /* a basic group read from messages.getFullChat, not a channel: the dialog is of kind 2 and only the fields a chatFull has are set */
    uint32_t admin_rights;          /* NOSHI_ADMIN_* of the account when it is an admin */
    char about[NOSHI_ABOUT_MAX];
    char username[NOSHI_CHANNEL_USERNAME_MAX];    /* empty for a private channel */
    char link[NOSHI_CHANNEL_LINK_MAX];            /* the invite link an admin sees, empty otherwise */
    int32_t participants;
    int32_t admins;
    int32_t banned;
    int32_t gifts;
    int32_t pinned_message;         /* the pinned message of the channel, zero for none */
    uint8_t has_linked;
    noshi_dialog_row linked;      /* the discussion group of a broadcast channel */
    /* who the account writes as here when it has chosen someone else than itself: a channel or an anonymous identity; zero for itself */
    int32_t send_as_kind;           /* 1 user, 3 channel, as noshi_peer; zero when none */
    int64_t send_as_id;
    noshi_chat_wallpaper wallpaper;
} noshi_full_channel;

/* channels.getFullChannel for a channel (kind 3 with an access hash) */
noshi_status noshi_full_channel_request(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out);
noshi_status noshi_discussion_request(noshi_arena *arena, const noshi_peer_ref *channel, int32_t post_id, noshi_tl_value **out);
noshi_status noshi_discussion_parse(const noshi_tl_value *answer, int64_t channel_id, noshi_dialog_row *out);
/* a messages.chatFull of that channel; now (unix seconds) decides whether a mute is still running; anything else,
   or a full chat that is not a channel, is NOSHI_E_MALFORMED. out is always initialised */
noshi_status noshi_full_channel_parse(const noshi_tl_value *answer, int64_t channel_id, int32_t now, noshi_full_channel *out);
/* messages.getFullChat for a basic group */
noshi_status noshi_full_chat_request(noshi_arena *arena, int64_t chat_id, noshi_tl_value **out);
/* a messages.chatFull of that basic group into the same row a channel fills, with basic set: the title, the description, the invite link, the mute, the
   pinned message, and the members and admins counted from the participants it lists (or the count of the chat when it lists none); anything else,
   or a full chat that is a channel's, is NOSHI_E_MALFORMED. out is always initialised */
noshi_status noshi_full_chat_parse(const noshi_tl_value *answer, int64_t chat_id, int32_t now, noshi_full_channel *out);
/* the NOSHI_ADMIN_* bits a chatAdminRights object sets; a missing or foreign object is none */
uint32_t noshi_admin_rights_read(const noshi_tl_value *rights);

typedef enum noshi_member_list {
    NOSHI_MEMBERS_RECENT = 0,     /* the subscribers, newest first; a query searches them by name */
    NOSHI_MEMBERS_ADMINS,
    NOSHI_MEMBERS_KICKED          /* the blacklist; a query searches it by name */
} noshi_member_list;

typedef enum noshi_member_role {
    NOSHI_MEMBER_PLAIN = 0,
    NOSHI_MEMBER_CREATOR,
    NOSHI_MEMBER_ADMIN,
    NOSHI_MEMBER_BANNED
} noshi_member_role;

typedef struct noshi_channel_member {
    noshi_person_row person;
    uint8_t role;                   /* noshi_member_role */
    uint8_t can_edit;               /* an admin whose rights the account may change */
    uint8_t self;                   /* the account itself */
    uint32_t rights;                /* NOSHI_ADMIN_* of an admin; every right for the creator */
    int32_t date;                   /* when the person joined, was promoted or was banned; zero when unknown */
    char rank[NOSHI_MEMBER_RANK_MAX];
} noshi_channel_member;

/* the inputChannel of a channel (kind 3 with an access hash); anything else is NOSHI_E_ARG */
noshi_status noshi_channel_input(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out);

/* channels.getParticipants for one page of a list */
noshi_status noshi_channel_members_request(noshi_arena *arena, const noshi_peer_ref *channel, noshi_member_list list, const char *query,
                                              int32_t offset, int32_t limit, noshi_tl_value **out);
/* the answer to it: rows in server order, at most cap, and the total the server counts for the list; participants
   that are not users, and users the answer does not describe, are left out */
noshi_status noshi_channel_members_parse(const noshi_tl_value *answer, noshi_channel_member *rows, size_t cap, size_t *count, int32_t *total);

/* channels.editAdmin: makes the user an admin with exactly these rights, or an ordinary subscriber again when
   rights is zero */
noshi_status noshi_channel_admin_request(noshi_arena *arena, const noshi_peer_ref *channel, const noshi_peer_ref *user, uint32_t rights,
                                            const char *rank, noshi_tl_value **out);
/* channels.editBanned: puts the user on the blacklist (the user is removed and cannot return), or takes the user off it again */
noshi_status noshi_channel_ban_request(noshi_arena *arena, const noshi_peer_ref *channel, const noshi_peer_ref *user, int banned,
                                          noshi_tl_value **out);
/* channels.inviteToChannel: adds these users (one to NOSHI_INVITE_MAX, each a user with an access hash) to the supergroup */
#define NOSHI_INVITE_MAX 20
noshi_status noshi_channel_invite_request(noshi_arena *arena, const noshi_peer_ref *channel, const noshi_peer_ref *users, size_t count,
                                             noshi_tl_value **out);
/* how many users messages.invitedUsers says could not be added, because of their privacy settings or for another reason of their own */
noshi_status noshi_channel_invite_missing(const noshi_tl_value *answer, size_t *missing);
/* channels.editTitle */
noshi_status noshi_channel_title_request(noshi_arena *arena, const noshi_peer_ref *channel, const char *title, noshi_tl_value **out);
/* messages.editChatAbout; an empty text clears the description */
noshi_status noshi_channel_about_request(noshi_arena *arena, const noshi_peer_ref *channel, const char *about, noshi_tl_value **out);
/* channels.updateUsername; an empty name makes the channel private. check asks channels.checkUsername instead, which only says whether it is free */
noshi_status noshi_channel_username_request(noshi_arena *arena, const noshi_peer_ref *channel, const char *username, int check,
                                               noshi_tl_value **out);
/* channels.toggleSignatures */
noshi_status noshi_channel_signatures_request(noshi_arena *arena, const noshi_peer_ref *channel, int enabled, noshi_tl_value **out);
/* a Bool answer: NOSHI_OK for true, NOSHI_E_STATE for false, NOSHI_E_MALFORMED for anything else */
noshi_status noshi_channel_bool_parse(const noshi_tl_value *answer);

/* channels.joinChannel */
noshi_status noshi_channel_join_request(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out);
/* the answer to it: NOSHI_OK when the account is in, NOSHI_E_UNSUPPORTED when the channel asks for a web view check first,
   NOSHI_E_MALFORMED for anything else */
noshi_status noshi_channel_join_parse(const noshi_tl_value *answer);
int noshi_channel_already_left(int peer_kind, const char *error_name);
/* channels.getParticipant for this account: the one answer that says whether it is in the channel, since the flags of a min channel say nothing about it */
noshi_status noshi_channel_member_request(noshi_arena *arena, const noshi_peer_ref *channel, noshi_tl_value **out);
/* the answer to it: *member is 1 for a creator, an admin or a plain member and 0 for one that left or is banned; NOSHI_E_MALFORMED for anything else. the error
   USER_NOT_PARTICIPANT of the request is "not in" too, which noshi_channel_already_left tells */
noshi_status noshi_channel_member_parse(const noshi_tl_value *answer, int *member);
/* resolves a min channel through the message that named it, without reusing its unusable hash */
noshi_status noshi_channel_from_message_request(noshi_arena *arena, const noshi_peer_ref *peer, int32_t message_id,
                                                   int64_t channel_id, noshi_tl_value **out);

/* channels.getChannels for one channel by the number and the hash this account knows it by, which a link to a post of a private channel only carries the number of */
noshi_status noshi_channel_by_id_request(noshi_arena *arena, int64_t channel_id, int64_t access_hash, noshi_tl_value **out);
/* the chat row of that channel from the answer; NOSHI_E_NOTFOUND when the answer holds no channel of that number (a forbidden one included),
   NOSHI_E_MALFORMED for any other answer */
noshi_status noshi_channel_dialog_parse(const noshi_tl_value *answer, int64_t channel_id, noshi_dialog_row *out);

#endif

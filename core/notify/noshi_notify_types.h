#ifndef NOSHI_NOTIFY_TYPES_H
#define NOSHI_NOTIFY_TYPES_H

#include <stdint.h>

/* the notification settings of one chat or one kind of chat, as the server holds them; the rules that use them are in noshi_notify_prefs.h */

#define NOSHI_SOUND_NAME_MAX 48
#define NOSHI_NOTIFY_MUTE_FOREVER 2147483647

typedef enum noshi_sound_kind {
    NOSHI_SOUND_DEFAULT = 0,
    NOSHI_SOUND_NONE,
    /* a tone of the app: data is the file name of the bundle, title the name the person sees */
    NOSHI_SOUND_LOCAL,
    /* a tone saved in the cloud of the account */
    NOSHI_SOUND_RINGTONE
} noshi_sound_kind;

typedef struct noshi_notify_sound {
    int32_t kind;
    int64_t ringtone_id;
    char title[NOSHI_SOUND_NAME_MAX];
    char data[NOSHI_SOUND_NAME_MAX];
} noshi_notify_sound;

/* what a peerNotifySettings holds */
typedef struct noshi_peer_notify {
    uint8_t has_mute;
    int32_t mute_until;         /* zero is on, a time in the past is on, NOSHI_NOTIFY_MUTE_FOREVER is off for good */
    uint8_t has_previews;
    uint8_t previews;           /* 1 shows the text of the message */
    uint8_t has_silent;
    uint8_t silent;             /* 1 delivers without a sound */
    uint8_t has_sound;
    noshi_notify_sound sound;
    uint8_t has_stories_muted;
    uint8_t stories_muted;
    uint8_t has_stories_hide_sender;
    uint8_t stories_hide_sender;
    uint8_t has_stories_sound;
    noshi_notify_sound stories_sound;
} noshi_peer_notify;

#endif

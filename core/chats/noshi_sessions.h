#ifndef NOSHI_SESSIONS_H
#define NOSHI_SESSIONS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_tl.h"

/* the devices screen: every session the account has, the one it runs on among them */

#define NOSHI_SESSION_TEXT_MAX 96
#define NOSHI_SESSION_SHORT_MAX 48
#define NOSHI_SESSIONS_MAX 100

typedef struct noshi_session_info {
    int64_t hash;                               /* names the session to every call below; zero for the current one, which cannot be ended */
    uint8_t current;                            /* the session this app runs on */
    uint8_t official_app;
    uint8_t password_pending;                   /* signed in, but the two step password has not been given yet */
    uint8_t secret_chats_off;                   /* encrypted_requests_disabled: this device does not take secret chats */
    uint8_t calls_off;                          /* call_requests_disabled */
    uint8_t unconfirmed;
    int32_t api_id;
    int32_t date_created;
    int32_t date_active;                        /* unix seconds; the session is online right now when current is set */
    char device_model[NOSHI_SESSION_TEXT_MAX];
    char platform[NOSHI_SESSION_SHORT_MAX];
    char system_version[NOSHI_SESSION_SHORT_MAX];
    char app_name[NOSHI_SESSION_SHORT_MAX];
    char app_version[NOSHI_SESSION_SHORT_MAX];
    char ip[NOSHI_SESSION_SHORT_MAX];
    char country[NOSHI_SESSION_TEXT_MAX];
    char region[NOSHI_SESSION_TEXT_MAX];
} noshi_session_info;

/* what drew an icon for a session: the kind picks the picture and the color of its circle SessionCell does */
typedef enum noshi_session_kind {
    NOSHI_SESSION_OTHER = 0,
    NOSHI_SESSION_IPHONE,
    NOSHI_SESSION_IPAD,
    NOSHI_SESSION_MAC,
    NOSHI_SESSION_WINDOWS,
    NOSHI_SESSION_LINUX,
    NOSHI_SESSION_UBUNTU,
    NOSHI_SESSION_ANDROID,
    NOSHI_SESSION_ANDROID_TABLET,
    NOSHI_SESSION_DESKTOP,
    NOSHI_SESSION_CHROME,
    NOSHI_SESSION_SAFARI,
    NOSHI_SESSION_EDGE,
    NOSHI_SESSION_FIREFOX,
    NOSHI_SESSION_OPERA,
    NOSHI_SESSION_WEB
} noshi_session_kind;

noshi_status noshi_sessions_request(noshi_arena *arena, noshi_tl_value **out);
/* an account.authorizations answer: the current session first, then the others as the server lists them */
noshi_status noshi_sessions_parse(const noshi_tl_value *answer, noshi_session_info *out, size_t cap, size_t *count, int32_t *ttl_days);

/* the kind of icon, from the platform, the device model and the app name, in the order SessionCell: browsers first
   (by the device model), then the operating systems, then the apps that say "desktop" */
noshi_session_kind noshi_session_kind_of(const noshi_session_info *session);

/* "iPhone4,1", or the platform and the system version when the device model is empty; always NUL terminated, empty
   only when all three are */
void noshi_session_title(const noshi_session_info *session, char *out, size_t cap);
/* "Telegram Android 13.1.0": the app and its version */
void noshi_session_app_line(const noshi_session_info *session, char *out, size_t cap);

/* account.resetAuthorization for one session other than this one; a hash of zero is NOSHI_E_ARG */
noshi_status noshi_session_end_request(noshi_arena *arena, int64_t hash, noshi_tl_value **out);
/* auth.resetAuthorizations: every session but this one */
noshi_status noshi_sessions_end_others_request(noshi_arena *arena, noshi_tl_value **out);
/* account.changeAuthorizationSettings: whether the session takes secret chats and calls; each of the two is -1 to
   leave it as it is, 0 for no and 1 for yes; both -1 is NOSHI_E_ARG */
noshi_status noshi_session_settings_request(noshi_arena *arena, int64_t hash, int secret_chats, int calls, noshi_tl_value **out);
/* account.setAuthorizationTTL; days is 1 to 365 */
noshi_status noshi_sessions_ttl_request(noshi_arena *arena, int32_t days, noshi_tl_value **out);
/* auth.acceptLoginToken: the person scanned the QR code of another device, whose login token is the url-safe base64 of the tg://login?token= link */
#define NOSHI_LOGIN_TOKEN_MAX 64
noshi_status noshi_login_token_from_link(const char *link, uint8_t *token, size_t cap, size_t *len);
noshi_status noshi_login_token_accept_request(noshi_arena *arena, const uint8_t *token, size_t len, noshi_tl_value **out);

#endif

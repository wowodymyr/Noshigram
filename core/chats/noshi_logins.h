#ifndef NOSHI_LOGINS_H
#define NOSHI_LOGINS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_status.h"
#include "noshi_tl.h"

/* a login the server does not trust yet: a session that signed in from a place the account has not been used from */

#define NOSHI_LOGIN_DEVICE_MAX 96
#define NOSHI_LOGIN_PLACE_MAX 96
#define NOSHI_LOGINS_MAX 8

typedef struct noshi_unconfirmed_login {
    int64_t hash;                           /* names the session to confirm or end */
    int32_t date;                           /* when it signed in, unix seconds */
    char device[NOSHI_LOGIN_DEVICE_MAX];  /* "iPhone4,1", or the app's name when the device is not given */
    char place[NOSHI_LOGIN_PLACE_MAX];    /* "frankfurt am Main, Germany"; empty when the server gives no place */
} noshi_unconfirmed_login;

noshi_status noshi_logins_request(noshi_arena *arena, noshi_tl_value **out);
/* an account.authorizations answer: the unconfirmed sessions other than this one, newest first */
noshi_status noshi_logins_parse(const noshi_tl_value *answer, noshi_unconfirmed_login *out, size_t cap, size_t *count);

/* account.changeAuthorizationSettings with confirmed: the owner says the login was theirs */
noshi_status noshi_login_confirm_request(noshi_arena *arena, int64_t hash, noshi_tl_value **out);
/* account.resetAuthorization: the owner says it was not them, and the session ends */
noshi_status noshi_login_reset_request(noshi_arena *arena, int64_t hash, noshi_tl_value **out);

#endif

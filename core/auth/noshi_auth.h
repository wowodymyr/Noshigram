#ifndef NOSHI_AUTH_H
#define NOSHI_AUTH_H

#include "noshi_mt_client.h"
#include "noshi_srp.h"

typedef enum noshi_auth_state {
    NOSHI_AUTH_IDLE = 0,
    NOSHI_AUTH_WAITING,
    NOSHI_AUTH_CODE,
    NOSHI_AUTH_EMAIL_SETUP,
    NOSHI_AUTH_EMAIL_CODE,
    NOSHI_AUTH_PASSWORD,
    NOSHI_AUTH_SIGNUP,
    NOSHI_AUTH_RECOVERY,
    NOSHI_AUTH_QR,
    NOSHI_AUTH_MIGRATE,
    NOSHI_AUTH_FLOOD_WAIT,
    NOSHI_AUTH_AUTHORIZED
} noshi_auth_state;

typedef struct noshi_auth_events {
    void *ctx;
    noshi_status (*submit)(void *ctx, uint64_t id, const noshi_tl_value *request);
    void (*cancel)(void *ctx, uint64_t id);
    void (*changed)(void *ctx, noshi_auth_state state, noshi_status status,
                    const noshi_tl_value *value, const char *error);
} noshi_auth_events;

typedef struct noshi_auth {
    noshi_auth_events events;
    const noshi_clock *clock;
    int32_t api_id;
    char api_hash[129];
    char phone[65];
    char code_hash[257];
    noshi_auth_state state;
    noshi_auth_state resume_state;
    uint64_t generation;
    uint64_t pending;
    uint64_t resend_at;
    uint64_t wait_until;
    int32_t migrate_dc;
    uint32_t migrations;
    uint32_t operation;
    int qr;
    int qr_import;
    int qr_refresh;
    int64_t server_time_offset_ms;
    /* monotonic deadline, so changing the wall clock cannot repeatedly replace a login code */
    uint64_t qr_expires;
    noshi_writer retry;
    noshi_arena password_arena;
    noshi_tl_value *password_info;
} noshi_auth;

noshi_status noshi_auth_init(noshi_auth *a, int32_t api_id, const char *api_hash,
                                const noshi_clock *clock, const noshi_auth_events *events);
void noshi_auth_cancel(noshi_auth *a);
void noshi_auth_free(noshi_auth *a);
noshi_status noshi_auth_phone(noshi_auth *a, const char *phone, const noshi_tl_value *settings);
noshi_status noshi_auth_code(noshi_auth *a, const char *code, const noshi_tl_value *email_verification);
noshi_status noshi_auth_resend(noshi_auth *a, const char *reason);
noshi_status noshi_auth_signup(noshi_auth *a, const char *first_name, const char *last_name);
noshi_status noshi_auth_password(noshi_auth *a, const uint8_t *password, size_t len);
noshi_status noshi_auth_recovery(noshi_auth *a);
noshi_status noshi_auth_recover_code(noshi_auth *a, const char *code);
noshi_status noshi_auth_email(noshi_auth *a, const char *email);
noshi_status noshi_auth_email_code(noshi_auth *a, const noshi_tl_value *verification);
noshi_status noshi_auth_qr(noshi_auth *a, const int64_t *except_ids, uint32_t count);
noshi_status noshi_auth_qr_refresh(noshi_auth *a);
noshi_status noshi_auth_resume(noshi_auth *a);
noshi_status noshi_auth_result(noshi_auth *a, uint64_t id, const noshi_mt_rpc_result *result);
noshi_status noshi_auth_tick(noshi_auth *a);
/* milliseconds until noshi_auth_tick has something to do (a request timeout or the end of a qr token), UINT32_MAX when it has nothing waiting */
uint32_t noshi_auth_next_ms(const noshi_auth *a);
noshi_status noshi_auth_qr_url(const noshi_tl_value *token, char *out, size_t cap);

#endif

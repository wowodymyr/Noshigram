#include "noshi_auth.h"

#include <stdio.h>
#include <string.h>

#include "noshi_tl_ids.h"

#define AUTH_ARENA (256u * 1024u)
#define AUTH_TIMEOUT 60000u

static uint64_t now(const noshi_auth *a) {
    return a->clock->monotonic_ms(a->clock->ctx);
}

static void changed(noshi_auth *a, noshi_auth_state state, noshi_status status,
                    const noshi_tl_value *value, const char *error) {
    a->state = state;
    if (a->events.changed) a->events.changed(a->events.ctx, state, status, value, error);
}

static void clear_retry(noshi_auth *a) {
    if (a->retry.data) noshi_wipe(a->retry.data, a->retry.cap);
    noshi_writer_free(&a->retry);
    noshi_writer_init(&a->retry, AUTH_ARENA);
}

static noshi_status text_copy(char *out, size_t cap, const char *in) {
    size_t n;
    if (!in) return NOSHI_E_ARG;
    n = strlen(in);
    if (n >= cap) return NOSHI_E_LIMIT;
    memcpy(out, in, n + 1);
    return NOSHI_OK;
}

static noshi_status send_request(noshi_auth *a, const noshi_tl_value *v, noshi_auth_state resume) {
    noshi_status status;
    uint64_t id;
    if (!a || !v || a->pending || a->state == NOSHI_AUTH_AUTHORIZED) return NOSHI_E_STATE;
    clear_retry(a);
    status = noshi_tl_encode(v, &a->retry, NULL);
    if (status != NOSHI_OK) { clear_retry(a); return status; }
    id = ++a->generation;
    if (!id) id = ++a->generation;
    a->pending = id;
    a->operation = noshi_tl_id(v);
    a->resume_state = resume;
    a->wait_until = now(a) + AUTH_TIMEOUT;
    a->state = NOSHI_AUTH_WAITING;
    status = a->events.submit(a->events.ctx, id, v);
    if (status != NOSHI_OK && a->pending == id) {
        a->pending = 0;
        clear_retry(a);
        changed(a, resume, status, NULL, NULL);
    }
    return status;
}

noshi_status noshi_auth_init(noshi_auth *a, int32_t api_id, const char *api_hash,
                                const noshi_clock *clock, const noshi_auth_events *events) {
    if (!a) return NOSHI_E_ARG;
    memset(a, 0, sizeof(*a));
    if (!events || !events->submit || api_id <= 0 || !api_hash || strlen(api_hash) != 32) return NOSHI_E_ARG;
    a->events = *events;
    a->clock = clock ? clock : &noshi_system_clock;
    if (!a->clock->monotonic_ms || !a->clock->realtime_ms) return NOSHI_E_ARG;
    a->api_id = api_id;
    memcpy(a->api_hash, api_hash, 33);
    noshi_writer_init(&a->retry, AUTH_ARENA);
    noshi_arena_init(&a->password_arena, AUTH_ARENA);
    return NOSHI_OK;
}

void noshi_auth_cancel(noshi_auth *a) {
    uint64_t id;
    if (!a) return;
    id = a->pending;
    a->pending = 0;
    ++a->generation;
    a->state = NOSHI_AUTH_IDLE;
    if (id && a->events.cancel) a->events.cancel(a->events.ctx, id);
    clear_retry(a);
    noshi_arena_free(&a->password_arena);
    a->password_info = NULL;
    noshi_wipe(a->phone, sizeof(a->phone));
    noshi_wipe(a->code_hash, sizeof(a->code_hash));
    a->qr = 0;
    a->qr_import = 0;
    a->qr_refresh = 0;
    a->migrations = 0;
    a->resend_at = 0;
    changed(a, NOSHI_AUTH_IDLE, NOSHI_OK, NULL, NULL);
}

void noshi_auth_free(noshi_auth *a) {
    if (!a) return;
    a->events.changed = NULL;
    noshi_auth_cancel(a);
    noshi_writer_free(&a->retry);
    noshi_wipe(a, sizeof(*a));
}

noshi_status noshi_auth_phone(noshi_auth *a, const char *phone, const noshi_tl_value *settings) {
    noshi_arena arena;
    noshi_tl_value *v, *default_settings;
    noshi_status status;
    size_t i, len;
    if (!a || !phone) return NOSHI_E_ARG;
    len = strlen(phone);
    if (len < 5 || len > 32) return NOSHI_E_ARG;
    for (i = phone[0] == '+' ? 1u : 0u; i < len; ++i) if (phone[i] < '0' || phone[i] > '9') return NOSHI_E_ARG;
    noshi_auth_cancel(a);
    status = text_copy(a->phone, sizeof(a->phone), phone);
    if (status != NOSHI_OK) return status;
    noshi_arena_init(&arena, AUTH_ARENA);
    v = noshi_tl_new_obj(&arena, "auth.sendCode");
    default_settings = settings ? NULL : noshi_tl_new_obj(&arena, "codeSettings");
    status = v ? noshi_tl_set_str(&arena, v, "phone_number", phone) : NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set_i32(&arena, v, "api_id", a->api_id);
    if (status == NOSHI_OK) status = noshi_tl_set_str(&arena, v, "api_hash", a->api_hash);
    if (status == NOSHI_OK) status = noshi_tl_set(v, "settings", (noshi_tl_value *)(settings ? settings : default_settings));
    if (status == NOSHI_OK) status = send_request(a, v, NOSHI_AUTH_IDLE);
    noshi_arena_free(&arena);
    return status;
}

static noshi_status phone_fields(noshi_auth *a, noshi_arena *arena, noshi_tl_value *v) {
    noshi_status status = v ? noshi_tl_set_str(arena, v, "phone_number", a->phone) : NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, v, "phone_code_hash", a->code_hash);
    return status;
}

noshi_status noshi_auth_code(noshi_auth *a, const char *code, const noshi_tl_value *email_verification) {
    noshi_arena arena;
    noshi_tl_value *v;
    noshi_status status;
    if (!a || a->state != NOSHI_AUTH_CODE || (!code && !email_verification) ||
        (code && (!*code || strlen(code) > 128))) return NOSHI_E_STATE;
    noshi_arena_init(&arena, AUTH_ARENA);
    v = noshi_tl_new_obj(&arena, "auth.signIn");
    status = phone_fields(a, &arena, v);
    if (status == NOSHI_OK && code) status = noshi_tl_set_str(&arena, v, "phone_code", code);
    if (status == NOSHI_OK && email_verification) status = noshi_tl_set(v, "email_verification", (noshi_tl_value *)email_verification);
    if (status == NOSHI_OK) status = send_request(a, v, NOSHI_AUTH_CODE);
    noshi_arena_free(&arena);
    return status;
}

noshi_status noshi_auth_resend(noshi_auth *a, const char *reason) {
    noshi_arena arena;
    noshi_tl_value *v;
    noshi_status status;
    if (!a || a->state != NOSHI_AUTH_CODE || now(a) < a->resend_at || (reason && strlen(reason) > 128)) return NOSHI_E_STATE;
    noshi_arena_init(&arena, AUTH_ARENA);
    v = noshi_tl_new_obj(&arena, "auth.resendCode");
    status = phone_fields(a, &arena, v);
    if (status == NOSHI_OK && reason) status = noshi_tl_set_str(&arena, v, "reason", reason);
    if (status == NOSHI_OK) status = send_request(a, v, NOSHI_AUTH_CODE);
    noshi_arena_free(&arena);
    return status;
}

noshi_status noshi_auth_signup(noshi_auth *a, const char *first_name, const char *last_name) {
    noshi_arena arena;
    noshi_tl_value *v;
    noshi_status status;
    if (!a || a->state != NOSHI_AUTH_SIGNUP || !first_name || !*first_name || !last_name ||
        strlen(first_name) > 256 || strlen(last_name) > 256) return NOSHI_E_STATE;
    noshi_arena_init(&arena, AUTH_ARENA);
    v = noshi_tl_new_obj(&arena, "auth.signUp");
    status = phone_fields(a, &arena, v);
    if (status == NOSHI_OK) status = noshi_tl_set_str(&arena, v, "first_name", first_name);
    if (status == NOSHI_OK) status = noshi_tl_set_str(&arena, v, "last_name", last_name);
    if (status == NOSHI_OK) status = send_request(a, v, NOSHI_AUTH_SIGNUP);
    noshi_arena_free(&arena);
    return status;
}

static noshi_status simple(noshi_auth *a, const char *name, const char *code, noshi_auth_state resume) {
    noshi_arena arena;
    noshi_tl_value *v;
    noshi_status status;
    noshi_arena_init(&arena, AUTH_ARENA);
    v = noshi_tl_new_obj(&arena, name);
    status = v ? NOSHI_OK : NOSHI_E_NOMEM;
    if (status == NOSHI_OK && code) status = noshi_tl_set_str(&arena, v, "code", code);
    if (status == NOSHI_OK) status = send_request(a, v, resume);
    noshi_arena_free(&arena);
    return status;
}

noshi_status noshi_auth_password(noshi_auth *a, const uint8_t *password, size_t len) {
    noshi_arena arena;
    noshi_tl_value *v, *proof_value;
    noshi_srp_proof proof;
    noshi_status status;
    if (!a || a->state != NOSHI_AUTH_PASSWORD || !a->password_info) return NOSHI_E_STATE;
    status = noshi_srp_check(a->password_info, password, len, &proof);
    if (status != NOSHI_OK) return status;
    noshi_arena_init(&arena, AUTH_ARENA);
    v = noshi_tl_new_obj(&arena, "auth.checkPassword");
    proof_value = noshi_tl_new_obj(&arena, "inputCheckPasswordSRP");
    status = proof_value && v ? noshi_tl_set_i64(&arena, proof_value, "srp_id", proof.id) : NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(&arena, proof_value, "A", proof.A, sizeof(proof.A));
    if (status == NOSHI_OK) status = noshi_tl_set_bytes(&arena, proof_value, "M1", proof.M1, sizeof(proof.M1));
    if (status == NOSHI_OK) status = noshi_tl_set(v, "password", proof_value);
    if (status == NOSHI_OK) status = send_request(a, v, NOSHI_AUTH_PASSWORD);
    noshi_wipe(&proof, sizeof(proof));
    noshi_arena_free(&arena);
    return status;
}

noshi_status noshi_auth_recovery(noshi_auth *a) {
    if (!a || a->state != NOSHI_AUTH_PASSWORD || !noshi_tl_has(a->password_info, "has_recovery")) return NOSHI_E_STATE;
    return simple(a, "auth.requestPasswordRecovery", NULL, NOSHI_AUTH_PASSWORD);
}

noshi_status noshi_auth_recover_code(noshi_auth *a, const char *code) {
    if (!a || a->state != NOSHI_AUTH_RECOVERY || !code || !*code || strlen(code) > 128) return NOSHI_E_STATE;
    return simple(a, "auth.recoverPassword", code, NOSHI_AUTH_RECOVERY);
}

static noshi_status email_request(noshi_auth *a, const char *email, const noshi_tl_value *verification) {
    noshi_arena arena;
    noshi_tl_value *v, *purpose;
    noshi_status status;
    noshi_arena_init(&arena, AUTH_ARENA);
    v = noshi_tl_new_obj(&arena, email ? "account.sendVerifyEmailCode" : "account.verifyEmail");
    purpose = noshi_tl_new_obj(&arena, "emailVerifyPurposeLoginSetup");
    status = phone_fields(a, &arena, purpose);
    if (status == NOSHI_OK && v) status = noshi_tl_set(v, "purpose", purpose);
    else if (!v) status = NOSHI_E_NOMEM;
    if (status == NOSHI_OK && email) status = noshi_tl_set_str(&arena, v, "email", email);
    if (status == NOSHI_OK && verification) status = noshi_tl_set(v, "verification", (noshi_tl_value *)verification);
    if (status == NOSHI_OK) status = send_request(a, v, a->state);
    noshi_arena_free(&arena);
    return status;
}

noshi_status noshi_auth_email(noshi_auth *a, const char *email) {
    if (!a || a->state != NOSHI_AUTH_EMAIL_SETUP || !email || !*email || strlen(email) > 320) return NOSHI_E_STATE;
    return email_request(a, email, NULL);
}

noshi_status noshi_auth_email_code(noshi_auth *a, const noshi_tl_value *verification) {
    if (!a || a->state != NOSHI_AUTH_EMAIL_CODE || !verification) return NOSHI_E_STATE;
    return email_request(a, NULL, verification);
}

noshi_status noshi_auth_qr(noshi_auth *a, const int64_t *except_ids, uint32_t count) {
    noshi_arena arena;
    noshi_tl_value *v;
    noshi_status status;
    if (!a || count > 1024 || (count && !except_ids)) return NOSHI_E_ARG;
    if (a->state != NOSHI_AUTH_QR && a->state != NOSHI_AUTH_IDLE) return NOSHI_E_STATE;
    noshi_arena_init(&arena, AUTH_ARENA);
    v = noshi_tl_new_obj(&arena, "auth.exportLoginToken");
    status = v ? noshi_tl_set_i32(&arena, v, "api_id", a->api_id) : NOSHI_E_NOMEM;
    if (status == NOSHI_OK) status = noshi_tl_set_str(&arena, v, "api_hash", a->api_hash);
    if (status == NOSHI_OK) status = noshi_tl_set_i64_vec(&arena, v, "except_ids", except_ids, count);
    a->qr = 1;
    a->qr_refresh = 0;
    if (status == NOSHI_OK) status = send_request(a, v, NOSHI_AUTH_QR);
    noshi_arena_free(&arena);
    return status;
}

noshi_status noshi_auth_qr_refresh(noshi_auth *a) {
    if (!a || !a->qr) return NOSHI_E_STATE;
    if (a->pending) { a->qr_refresh = 1; return NOSHI_OK; }
    if (a->state != NOSHI_AUTH_QR) return NOSHI_E_STATE;
    return noshi_auth_qr(a, NULL, 0);
}

static noshi_status sent_code(noshi_auth *a, const noshi_tl_value *v) {
    const uint8_t *hash;
    size_t len;
    int32_t timeout = 0;
    const noshi_tl_value *type;
    if (noshi_tl_get_bytes(v, "phone_code_hash", &hash, &len) != NOSHI_OK || len == 0 ||
        len >= sizeof(a->code_hash) || memchr(hash, 0, len)) return NOSHI_E_MALFORMED;
    memcpy(a->code_hash, hash, len); a->code_hash[len] = 0;
    if (noshi_tl_has(v, "timeout") && noshi_tl_get_i32(v, "timeout", &timeout) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (timeout < 0) return NOSHI_E_MALFORMED;
    a->resend_at = noshi_tl_has(v, "next_type") ? now(a) + (uint64_t)timeout * 1000u : UINT64_MAX;
    type = noshi_tl_get(v, "type");
    changed(a, noshi_tl_is(type, NOSHI_TL_ID_auth_sentCodeTypeSetUpEmailRequired) ?
            NOSHI_AUTH_EMAIL_SETUP : NOSHI_AUTH_CODE, NOSHI_OK, v, NULL);
    return NOSHI_OK;
}

noshi_status noshi_auth_resume(noshi_auth *a) {
    noshi_arena arena;
    noshi_tl_value *v;
    noshi_status status;
    uint64_t id;
    if (!a || (a->state != NOSHI_AUTH_MIGRATE && a->state != NOSHI_AUTH_FLOOD_WAIT) || a->pending)
        return NOSHI_E_STATE;
    if (a->state == NOSHI_AUTH_FLOOD_WAIT && now(a) < a->wait_until) return NOSHI_E_RETRY;
    if (a->qr_import) {
        a->qr_import = 0;
        a->state = NOSHI_AUTH_QR;
    }
    noshi_arena_init(&arena, AUTH_ARENA);
    status = noshi_tl_decode_all(&arena, NULL, NOSHI_TL_REF_ANY, a->retry.data, a->retry.len, &v);
    if (status == NOSHI_OK) {
        id = ++a->generation;
        a->pending = id;
        a->state = NOSHI_AUTH_WAITING;
        a->wait_until = now(a) + AUTH_TIMEOUT;
        status = a->events.submit(a->events.ctx, id, v);
        if (status != NOSHI_OK && a->pending == id) { a->pending = 0; changed(a, a->resume_state, status, NULL, NULL); }
    }
    noshi_arena_free(&arena);
    return status;
}

noshi_status noshi_auth_result(noshi_auth *a, uint64_t id, const noshi_mt_rpc_result *r) {
    noshi_status status = NOSHI_OK;
    const noshi_tl_value *v;
    uint32_t operation;
    if (!a || !r) return NOSHI_E_ARG;
    if (!id || id != a->pending) return NOSHI_E_NOTFOUND;
    a->pending = 0;
    operation = a->operation;
    if (r->status != NOSHI_OK) {
        char name[128];
        int32_t number;
        noshi_mt_rpc_error_split(r->error_text, name, sizeof(name), &number);
        if (r->status == NOSHI_E_RPC && !strcmp(name, "SESSION_PASSWORD_NEEDED")) {
            clear_retry(a);
            a->state = NOSHI_AUTH_PASSWORD;
            return simple(a, "account.getPassword", NULL, NOSHI_AUTH_PASSWORD);
        }
        if (r->status == NOSHI_E_RPC && !strcmp(name, "SRP_ID_INVALID")) {
            clear_retry(a);
            a->state = NOSHI_AUTH_PASSWORD;
            return simple(a, "account.getPassword", NULL, NOSHI_AUTH_PASSWORD);
        }
        if (r->status == NOSHI_E_RPC && number > 0 &&
            (!strcmp(name, "PHONE_MIGRATE") || !strcmp(name, "NETWORK_MIGRATE") || !strcmp(name, "USER_MIGRATE"))) {
            if (++a->migrations > 3 || number > 1000) status = NOSHI_E_LIMIT;
            else { a->migrate_dc = number; changed(a, NOSHI_AUTH_MIGRATE, r->status, NULL, r->error_text); return NOSHI_OK; }
        } else if (r->status == NOSHI_E_RPC && number > 0 &&
                   (!strcmp(name, "FLOOD_WAIT") || !strcmp(name, "FLOOD_PREMIUM_WAIT"))) {
            a->wait_until = now(a) + (uint64_t)number * 1000u;
            changed(a, NOSHI_AUTH_FLOOD_WAIT, r->status, NULL, r->error_text);
            return NOSHI_OK;
        } else status = r->status;
        clear_retry(a);
        changed(a, a->resume_state, status, NULL, r->error_text);
        return status;
    }
    v = r->value;
    if (!v) status = NOSHI_E_MALFORMED;
    else if (noshi_tl_is(v, NOSHI_TL_ID_auth_sentCode)) {
        clear_retry(a);
        return sent_code(a, v);
    } else if (noshi_tl_is(v, NOSHI_TL_ID_auth_sentCodeSuccess) || noshi_tl_is(v, NOSHI_TL_ID_auth_loginTokenSuccess)) {
        v = noshi_tl_get(v, "authorization");
        if (!v) status = NOSHI_E_MALFORMED;
    }
    if (status == NOSHI_OK && noshi_tl_is(v, NOSHI_TL_ID_auth_authorization)) {
        clear_retry(a);
        noshi_arena_free(&a->password_arena);
        a->password_info = NULL;
        changed(a, NOSHI_AUTH_AUTHORIZED, NOSHI_OK, v, NULL);
        return NOSHI_OK;
    }
    if (status == NOSHI_OK && noshi_tl_is(v, NOSHI_TL_ID_auth_authorizationSignUpRequired)) {
        clear_retry(a);
        changed(a, NOSHI_AUTH_SIGNUP, NOSHI_OK, v, NULL);
        return NOSHI_OK;
    }
    if (status == NOSHI_OK && operation == NOSHI_TL_ID_account_getPassword && noshi_tl_is(v, NOSHI_TL_ID_account_password)) {
        noshi_writer w;
        noshi_writer_init(&w, AUTH_ARENA);
        noshi_arena_free(&a->password_arena);
        a->password_info = NULL;
        status = noshi_tl_encode(v, &w, NULL);
        if (status == NOSHI_OK) status = noshi_tl_decode_all(&a->password_arena, NULL, NOSHI_TL_REF_ANY,
                                                               w.data, w.len, &a->password_info);
        noshi_writer_free(&w);
        clear_retry(a);
        changed(a, NOSHI_AUTH_PASSWORD, status, v, NULL);
        return status;
    }
    if (status == NOSHI_OK && noshi_tl_is(v, NOSHI_TL_ID_auth_passwordRecovery)) {
        clear_retry(a);
        changed(a, NOSHI_AUTH_RECOVERY, NOSHI_OK, v, NULL);
        return NOSHI_OK;
    }
    if (status == NOSHI_OK && noshi_tl_is(v, NOSHI_TL_ID_account_sentEmailCode)) {
        clear_retry(a);
        changed(a, NOSHI_AUTH_EMAIL_CODE, NOSHI_OK, v, NULL);
        return NOSHI_OK;
    }
    if (status == NOSHI_OK && noshi_tl_is(v, NOSHI_TL_ID_account_emailVerifiedLogin)) {
        clear_retry(a);
        return sent_code(a, noshi_tl_get(v, "sent_code"));
    }
    if (status == NOSHI_OK && noshi_tl_is(v, NOSHI_TL_ID_auth_loginToken)) {
        int32_t expires;
        if (noshi_tl_get_i32(v, "expires", &expires) != NOSHI_OK || expires < 0) status = NOSHI_E_MALFORMED;
        else {
            int64_t server_now = (int64_t)a->clock->realtime_ms(a->clock->ctx) + a->server_time_offset_ms;
            int64_t remaining = (int64_t)expires * 1000 - server_now;
            /* an already expired server token waits one second instead of spinning the worker and blinking the code */
            a->qr_expires = now(a) + (uint64_t)(remaining > 1000 ? remaining : 1000);
            clear_retry(a);
            changed(a, NOSHI_AUTH_QR, NOSHI_OK, v, NULL);
            if (a->qr_refresh) return noshi_auth_qr_refresh(a);
            return NOSHI_OK;
        }
    }
    if (status == NOSHI_OK && noshi_tl_is(v, NOSHI_TL_ID_auth_loginTokenMigrateTo)) {
        noshi_arena arena;
        noshi_tl_value *request;
        const uint8_t *token;
        size_t len;
        if (noshi_tl_get_i32(v, "dc_id", &a->migrate_dc) != NOSHI_OK || a->migrate_dc <= 0 ||
            noshi_tl_get_bytes(v, "token", &token, &len) != NOSHI_OK || !len || len > 4096 || ++a->migrations > 3)
            status = NOSHI_E_MALFORMED;
        else {
            noshi_arena_init(&arena, AUTH_ARENA);
            request = noshi_tl_new_obj(&arena, "auth.importLoginToken");
            status = request ? noshi_tl_set_bytes(&arena, request, "token", token, len) : NOSHI_E_NOMEM;
            clear_retry(a);
            if (status == NOSHI_OK) status = noshi_tl_encode(request, &a->retry, NULL);
            noshi_arena_free(&arena);
            if (status == NOSHI_OK) {
                a->operation = NOSHI_TL_ID_auth_importLoginToken;
                a->qr_import = 1;
                a->resume_state = NOSHI_AUTH_QR;
                changed(a, NOSHI_AUTH_MIGRATE, NOSHI_OK, v, NULL);
                return NOSHI_OK;
            }
        }
    }
    if (status == NOSHI_OK) status = NOSHI_E_UNSUPPORTED;
    clear_retry(a);
    changed(a, a->resume_state, status, v, NULL);
    return status;
}

noshi_status noshi_auth_tick(noshi_auth *a) {
    if (!a) return NOSHI_E_ARG;
    if (a->pending && now(a) >= a->wait_until) {
        uint64_t id = a->pending;
        a->pending = 0;
        if (a->events.cancel) a->events.cancel(a->events.ctx, id);
        clear_retry(a);
        changed(a, a->resume_state, NOSHI_E_TIMEOUT, NULL, NULL);
        return NOSHI_E_TIMEOUT;
    }
    if (!a->pending && a->state == NOSHI_AUTH_QR && now(a) >= a->qr_expires)
        return noshi_auth_qr_refresh(a);
    return NOSHI_OK;
}

uint32_t noshi_auth_next_ms(const noshi_auth *a) {
    uint64_t next = UINT64_MAX;
    if (!a) return UINT32_MAX;
    if (a->pending) {
        uint64_t at = now(a);
        next = a->wait_until > at ? a->wait_until - at : 0;
    }
    if (!a->pending && a->state == NOSHI_AUTH_QR) {
        uint64_t at = now(a), left = a->qr_expires > at ? a->qr_expires - at : 0;
        if (left < next) next = left;
    }
    return next > 0xfffffffeu ? UINT32_MAX : (uint32_t)next;
}

noshi_status noshi_auth_qr_url(const noshi_tl_value *v, char *out, size_t cap) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const uint8_t *token;
    size_t len, i, pos = 0;
    uint32_t bits = 0;
    unsigned count = 0;
    const char prefix[] = "tg://login?token=";
    if (!out || !cap) return NOSHI_E_ARG;
    out[0] = 0;
    if (noshi_tl_get_bytes(v, "token", &token, &len) != NOSHI_OK || !len || len > 4096) return NOSHI_E_ARG;
    if (sizeof(prefix) + (len * 8 + 5) / 6 > cap) return NOSHI_E_LIMIT;
    memcpy(out, prefix, sizeof(prefix) - 1); pos = sizeof(prefix) - 1;
    for (i = 0; i < len; ++i) {
        bits = (bits << 8) | token[i]; count += 8;
        while (count >= 6) { count -= 6; out[pos++] = alphabet[(bits >> count) & 63u]; }
    }
    if (count) out[pos++] = alphabet[(bits << (6 - count)) & 63u];
    out[pos] = 0;
    return NOSHI_OK;
}

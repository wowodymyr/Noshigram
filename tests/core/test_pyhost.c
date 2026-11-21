#include "noshi_pyhost.h"
#include "test_util.h"

#ifndef FIXTURE_DIR
#error FIXTURE_DIR is set by the makefile
#endif
#ifndef PY_STDLIB
#error PY_STDLIB is set by the makefile
#endif

static char g_seen_name[64];
static char g_seen_payload[128];

static noshi_status services(void *ctx, const char *name, const char *payload, size_t payload_len,
                               char *out, size_t cap, size_t *out_len) {
    (void)ctx;
    snprintf(g_seen_name, sizeof g_seen_name, "%s", name);
    snprintf(g_seen_payload, sizeof g_seen_payload, "%.*s", (int)payload_len, payload);
    const char *reply = "{\"ok\":true}";
    noshi_status status = NOSHI_OK;
    if (strcmp(name, "echo") == 0) {
        reply = payload;
        if (payload_len < cap) {
            memcpy(out, payload, payload_len);
            *out_len = payload_len;
            return NOSHI_OK;
        }
    } else if (strcmp(name, "deny") == 0) {
        reply = "not granted";
        status = NOSHI_E_SECURITY;
    } else if (strcmp(name, "missing") == 0) {
        status = NOSHI_E_NOTFOUND;
        reply = "";
    } else if (strcmp(name, "bad") == 0) {
        status = NOSHI_E_ARG;
        reply = "bad arg";
    }
    size_t n = strlen(reply);
    if (n > cap) n = cap;
    memcpy(out, reply, n);
    *out_len = n;
    return status;
}

static noshi_status call(const char *fn, const char *args, uint32_t timeout, char *out, size_t cap) {
    size_t len = 0;
    return noshi_pyhost_call("fixture", fn, args, timeout, out, cap, &len);
}

static void rejects_bad_config(void) {
    noshi_pyhost_config cfg;
    memset(&cfg, 0, sizeof cfg);
    CHECK_EQ_INT(noshi_pyhost_init(NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_pyhost_init(&cfg), NOSHI_E_ARG);
    char out[64];
    size_t len;
    CHECK_EQ_INT(noshi_pyhost_call("fixture", "add", "[1,2]", 0, out, sizeof out, &len), NOSHI_E_STATE);
}

static void starts(void) {
    noshi_pyhost_config cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.stdlib = PY_STDLIB;
    cfg.paths[0] = FIXTURE_DIR;
    cfg.service = services;
    CHECK_EQ_INT(noshi_pyhost_init(&cfg), NOSHI_OK);
    CHECK_EQ_INT(noshi_pyhost_init(&cfg), NOSHI_E_STATE);
}

static void calls_and_returns_json(void) {
    char out[256];
    CHECK_EQ_INT(call("add", "[2,3]", 0, out, sizeof out), NOSHI_OK);
    CHECK(strcmp(out, "5") == 0);
    CHECK_EQ_INT(call("echo", "[{\"a\":[1,\"\\u00e9\"]}]", 0, out, sizeof out), NOSHI_OK);
    CHECK(strcmp(out, "{\"a\": [1, \"\\u00e9\"]}") == 0);
    CHECK_EQ_INT(call("nothing", "[]", 0, out, sizeof out), NOSHI_OK);
    CHECK(strcmp(out, "null") == 0);
}

static void reports_failures(void) {
    char out[64];
    CHECK_EQ_INT(call("boom", "[]", 0, out, sizeof out), NOSHI_E_STATE);
    CHECK(strstr(noshi_pyhost_error(), "ValueError: boom") != NULL);
    CHECK_EQ_INT(call("denied", "[]", 0, out, sizeof out), NOSHI_E_SECURITY);
    CHECK_EQ_INT(call("add", "[1]", 0, out, sizeof out), NOSHI_E_STATE);
    CHECK_EQ_INT(call("nope", "[]", 0, out, sizeof out), NOSHI_E_STATE);
    CHECK(strstr(noshi_pyhost_error(), "AttributeError") != NULL);
    CHECK_EQ_INT(noshi_pyhost_call("no_such_module", "f", "[]", 0, out, sizeof out, NULL), NOSHI_E_STATE);
    CHECK(strstr(noshi_pyhost_error(), "ModuleNotFoundError") != NULL);
    CHECK_EQ_INT(call("add", "{", 0, out, sizeof out), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(call("add", "{\"a\":1}", 0, out, sizeof out), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(call("not_json", "[]", 0, out, sizeof out), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(call("big", "[100]", 0, out, sizeof out), NOSHI_E_LIMIT);
    CHECK_EQ_INT(call("big", "[60]", 0, out, sizeof out), NOSHI_OK);
    CHECK_EQ_INT(noshi_pyhost_call("fixture", "add", "[1,2]", 0, out, 1, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_pyhost_call(NULL, "add", "[1,2]", 0, out, sizeof out, NULL), NOSHI_E_ARG);
    CHECK_EQ_INT(call("add", "[1,2]", 0, out, sizeof out), NOSHI_OK);
    CHECK(noshi_pyhost_error()[0] == 0);
}

static void rejects_oversized_arguments(void) {
    char *big = malloc(NOSHI_PYHOST_ARGS_MAX + 16);
    char out[16];
    CHECK(big != NULL);
    if (!big) return;
    memset(big, ' ', NOSHI_PYHOST_ARGS_MAX + 8);
    big[NOSHI_PYHOST_ARGS_MAX + 8] = 0;
    CHECK_EQ_INT(call("add", big, 0, out, sizeof out), NOSHI_E_LIMIT);
    free(big);
}

static void stops_a_runaway_loop(void) {
    char out[16];
    CHECK_EQ_INT(call("spin", "[]", 100, out, sizeof out), NOSHI_E_TIMEOUT);
    CHECK_EQ_INT(call("spin", "[]", 100, out, sizeof out), NOSHI_E_TIMEOUT);
    /* the stale exception must not hit the call that follows */
    for (int i = 0; i < 50; ++i) CHECK_EQ_INT(call("add", "[1,1]", 200, out, sizeof out), NOSHI_OK);
}

static void talks_to_services(void) {
    char out[128];
    CHECK_EQ_INT(call("service", "[\"echo\",\"{\\\"a\\\":1}\"]", 0, out, sizeof out), NOSHI_OK);
    CHECK(strcmp(out, "\"{\\\"a\\\":1}\"") == 0);
    CHECK(strcmp(g_seen_name, "echo") == 0);
    CHECK(strcmp(g_seen_payload, "{\"a\":1}") == 0);
    CHECK_EQ_INT(call("service", "[\"ping\",\"{}\"]", 0, out, sizeof out), NOSHI_OK);
    CHECK(strcmp(out, "\"{\\\"ok\\\":true}\"") == 0);
    CHECK_EQ_INT(call("service_error", "[\"deny\"]", 0, out, sizeof out), NOSHI_OK);
    CHECK(strcmp(out, "\"PermissionError\"") == 0);
    CHECK_EQ_INT(call("service_error", "[\"missing\"]", 0, out, sizeof out), NOSHI_OK);
    CHECK(strcmp(out, "\"LookupError\"") == 0);
    CHECK_EQ_INT(call("service_error", "[\"bad\"]", 0, out, sizeof out), NOSHI_OK);
    CHECK(strcmp(out, "\"ValueError\"") == 0);
    CHECK_EQ_INT(call("service_error", "[\"other\"]", 0, out, sizeof out), NOSHI_OK);
    CHECK(strcmp(out, "\"none\"") == 0);
}

int main(void) {
    rejects_bad_config();
    starts();
    calls_and_returns_json();
    reports_failures();
    rejects_oversized_arguments();
    stops_a_runaway_loop();
    talks_to_services();
    noshi_pyhost_shutdown();
    if (g_failures) {
        fprintf(stderr, "test_pyhost: %d of %d checks failed\n", g_failures, g_checks);
        return 1;
    }
    printf("test_pyhost: %d checks passed\n", g_checks);
    return 0;
}

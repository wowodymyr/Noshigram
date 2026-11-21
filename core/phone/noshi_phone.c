#include "noshi_phone.h"

#include <stdio.h>
#include <string.h>

#define PHONE_MIN_TOTAL_DIGITS 7
#define PHONE_MIN_NATIONAL_DIGITS 4

size_t noshi_phone_digits(const char *in, char *out, size_t cap) {
    size_t n = 0;
    if (!out || cap == 0) return 0;
    out[0] = '\0';
    if (!in) return 0;
    for (; *in && n + 1 < cap; ++in) {
        if (*in >= '0' && *in <= '9') out[n++] = *in;
    }
    out[n] = '\0';
    return n;
}

noshi_status noshi_phone_format(const char *pattern, const char *digits, char *out, size_t cap) {
    char pending[sizeof(((noshi_country *)0)->pattern)];
    size_t pending_len = 0;
    size_t used = 0;
    if (!out || cap == 0) return NOSHI_E_ARG;
    out[0] = '\0';
    if (!pattern || !digits) return NOSHI_E_ARG;
    for (; *pattern && *digits; ++pattern) {
        if (*pattern == 'X') {
            if (used + pending_len + 2 > cap) return NOSHI_E_LIMIT;
            memcpy(out + used, pending, pending_len);
            used += pending_len;
            pending_len = 0;
            out[used++] = *digits++;
        } else {
            if (pending_len == sizeof(pending)) return NOSHI_E_LIMIT;
            pending[pending_len++] = *pattern;
        }
    }
    /* digits beyond the pattern follow without grouping */
    if (*digits) {
        if (used + pending_len + 1 > cap) return NOSHI_E_LIMIT;
        memcpy(out + used, pending, pending_len);
        used += pending_len;
    }
    while (*digits) {
        if (used + 2 > cap) return NOSHI_E_LIMIT;
        out[used++] = *digits++;
    }
    out[used] = '\0';
    return NOSHI_OK;
}

int noshi_phone_valid(size_t code_digits, size_t national_digits) {
    size_t total = code_digits + national_digits;
    return code_digits >= 1 && code_digits <= NOSHI_COUNTRY_CODE_MAX &&
           national_digits >= PHONE_MIN_NATIONAL_DIGITS &&
           total >= PHONE_MIN_TOTAL_DIGITS && total <= NOSHI_PHONE_MAX_DIGITS;
}

static int is_digit(char c) {
    return c >= '0' && c <= '9';
}

static int pattern_char_ok(char c) {
    return c == 'X' || c == ' ' || c == '-' || c == '(' || c == ')';
}

static noshi_status parse_line(const char *line, size_t len, noshi_country *entry) {
    const char *field[4];
    size_t field_len[4];
    size_t fields = 0;
    size_t start = 0;
    size_t i;
    memset(entry, 0, sizeof(*entry));
    for (i = 0; i <= len; ++i) {
        if (i == len || line[i] == ';') {
            if (fields == 4) return NOSHI_E_MALFORMED;
            field[fields] = line + start;
            field_len[fields++] = i - start;
            start = i + 1;
        }
    }
    if (fields < 3) return NOSHI_E_MALFORMED;
    if (field_len[0] < 1 || field_len[0] > NOSHI_COUNTRY_CODE_MAX) return NOSHI_E_MALFORMED;
    for (i = 0; i < field_len[0]; ++i) {
        if (!is_digit(field[0][i])) return NOSHI_E_MALFORMED;
    }
    if (field_len[1] != 2 || field[1][0] < 'A' || field[1][0] > 'Z' || field[1][1] < 'A' || field[1][1] > 'Z') {
        return NOSHI_E_MALFORMED;
    }
    if (field_len[2] < 1 || field_len[2] >= sizeof(entry->name)) return NOSHI_E_MALFORMED;
    if (fields == 4) {
        if (field_len[3] >= sizeof(entry->pattern)) return NOSHI_E_MALFORMED;
        size_t kept = 0;
        for (i = 0; i < field_len[3]; ++i) {
            /* a few patterns spell out leading digits; echoing them would feed them back as typed digits */
            if (is_digit(field[3][i])) continue;
            if (!pattern_char_ok(field[3][i])) return NOSHI_E_MALFORMED;
            if (kept == 0 && field[3][i] != 'X') continue;
            entry->pattern[kept++] = field[3][i];
        }
    }
    memcpy(entry->code, field[0], field_len[0]);
    memcpy(entry->iso, field[1], 2);
    memcpy(entry->name, field[2], field_len[2]);
    return NOSHI_OK;
}

noshi_status noshi_country_parse(const char *text, size_t len, noshi_country *out, size_t cap,
                                     size_t *count) {
    size_t n = 0;
    size_t pos = 0;
    if (count) *count = 0;
    if (!text || !out || !count) return NOSHI_E_ARG;
    while (pos < len) {
        size_t end = pos;
        size_t line_len;
        while (end < len && text[end] != '\n') ++end;
        line_len = end - pos;
        if (line_len > 0 && text[pos + line_len - 1] == '\r') --line_len;
        if (line_len > 0) {
            noshi_status status;
            if (n == cap) return NOSHI_E_LIMIT;
            status = parse_line(text + pos, line_len, &out[n]);
            if (status != NOSHI_OK) return status;
            ++n;
        }
        pos = end + 1;
    }
    *count = n;
    return NOSHI_OK;
}

const noshi_country *noshi_country_match(const noshi_country *list, size_t count,
                                             const char *digits, size_t *code_len) {
    const noshi_country *best = NULL;
    size_t best_len = 0;
    size_t i;
    if (code_len) *code_len = 0;
    if (!list || !digits) return NULL;
    for (i = 0; i < count; ++i) {
        size_t len = strlen(list[i].code);
        if (len >= best_len && strncmp(list[i].code, digits, len) == 0) {
            best = &list[i];
            best_len = len;
        }
    }
    if (code_len) *code_len = best_len;
    return best;
}

noshi_status noshi_phone_display(const noshi_country *list, size_t count, const char *digits, char *out, size_t cap) {
    size_t code_len = 0;
    char grouped[NOSHI_PHONE_MAX_DIGITS * 3];
    if (!out || cap == 0) return NOSHI_E_ARG;
    out[0] = '\0';
    if (!list || !digits) return NOSHI_E_ARG;
    const noshi_country *hit = noshi_country_match(list, count, digits, &code_len);
    const char *pattern = hit ? hit->pattern : "";
    if (hit && code_len == 1 && hit->code[0] == '1') pattern = "(XXX) XXX-XX-XX";
    if (!hit || !*pattern || !digits[code_len]) {
        int n = snprintf(out, cap, "+%s", digits);
        return n > 0 && (size_t)n < cap ? NOSHI_OK : NOSHI_E_LIMIT;
    }
    noshi_status status = noshi_phone_format(pattern, digits + code_len, grouped, sizeof(grouped));
    if (status != NOSHI_OK) return status;
    int n = snprintf(out, cap, "+%.*s %s", (int)code_len, digits, grouped);
    return n > 0 && (size_t)n < cap ? NOSHI_OK : NOSHI_E_LIMIT;
}

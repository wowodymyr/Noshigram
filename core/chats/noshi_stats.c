#include "noshi_stats.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "noshi_store.h"
#include "noshi_tgc_json.h"
#include "noshi_tl_ids.h"

void noshi_chart_free(noshi_chart *chart) {
    uint32_t i;
    if (!chart) return;
    for (i = 0; i < NOSHI_CHART_LINES_MAX; ++i) free(chart->lines[i].y);
    free(chart->x);
    free(chart);
}

/* the text of a string member, NULL when it is missing or something else */
static const char *member_text(const noshi_json *object, const char *key, size_t *len) {
    return noshi_json_string(noshi_json_get(object, key), len);
}

static int member_flag(const noshi_json *object, const char *key) {
    int value = 0;
    const noshi_json *node = noshi_json_get(object, key);
    return node && noshi_json_bool(node, &value) == NOSHI_OK && value;
}

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* the server writes colors as #rrggbb; anything else keeps the neutral gray */
static uint32_t read_color(const noshi_json *colors, const char *id) {
    size_t len;
    const char *text = member_text(colors, id, &len);
    uint32_t value = 0;
    size_t i;
    if (!text || len != 7 || text[0] != '#') return 0x8e8e93u;
    for (i = 1; i < 7; ++i) {
        int digit = hex_digit(text[i]);
        if (digit < 0) return 0x8e8e93u;
        value = (value << 4) | (uint32_t)digit;
    }
    return value;
}

static int kind_of(const char *name) {
    if (!strcmp(name, "line")) return NOSHI_CHART_LINE;
    if (!strcmp(name, "bar")) return NOSHI_CHART_BAR;
    if (!strcmp(name, "area")) return NOSHI_CHART_AREA;
    if (!strcmp(name, "step")) return NOSHI_CHART_STEP;
    return 0;
}

/* the numbers of a column after its id, into a fresh array of exactly that many */
static noshi_status read_values(const noshi_json *column, uint32_t *count, int64_t **out) {
    size_t total = noshi_json_count(column);
    const noshi_json *item;
    int64_t *values;
    uint32_t n = 0;
    *out = NULL;
    if (total < 2) return NOSHI_E_MALFORMED;
    if (total - 1 > NOSHI_CHART_POINTS_MAX) return NOSHI_E_LIMIT;
    values = calloc(total - 1, sizeof(*values));
    if (!values) return NOSHI_E_NOMEM;
    for (item = noshi_json_next(noshi_json_first(column)); item; item = noshi_json_next(item)) {
        if (noshi_json_int(item, &values[n]) != NOSHI_OK) {
            free(values);
            return NOSHI_E_MALFORMED;
        }
        ++n;
    }
    *count = n;
    *out = values;
    return NOSHI_OK;
}

noshi_status noshi_chart_parse(const char *json, size_t len, noshi_chart **out) {
    noshi_json_doc *doc = NULL;
    const noshi_json *root, *columns, *types, *names, *colors, *column;
    noshi_chart *chart;
    noshi_status status;
    uint32_t line_points[NOSHI_CHART_LINES_MAX];
    uint32_t i;
    char x_id[32] = "x";
    if (out) *out = NULL;
    if (!json || !out || !len) return NOSHI_E_ARG;
    status = noshi_json_parse(json, len, &doc);
    if (status != NOSHI_OK) return status == NOSHI_E_LIMIT ? NOSHI_E_LIMIT : NOSHI_E_MALFORMED;
    root = noshi_json_root(doc);
    columns = noshi_json_get(root, "columns");
    types = noshi_json_get(root, "types");
    names = noshi_json_get(root, "names");
    colors = noshi_json_get(root, "colors");
    if (noshi_json_kind(columns) != NOSHI_JSON_ARRAY || noshi_json_kind(types) != NOSHI_JSON_OBJECT) {
        noshi_json_free(doc);
        return NOSHI_E_MALFORMED;
    }
    chart = calloc(1, sizeof(*chart));
    if (!chart) {
        noshi_json_free(doc);
        return NOSHI_E_NOMEM;
    }
    /* the type "x" marks the column of the time axis, whatever id it has */
    for (column = noshi_json_first(types); column; column = noshi_json_next(column)) {
        const char *kind = noshi_json_string(column, NULL), *key = noshi_json_key(column);
        if (kind && key && !strcmp(kind, "x") && strlen(key) < sizeof(x_id)) {
            strcpy(x_id, key);
            break;
        }
    }
    status = NOSHI_OK;
    for (column = noshi_json_first(columns); column && status == NOSHI_OK; column = noshi_json_next(column)) {
        const char *id, *name, *kind_text;
        size_t name_len;
        uint32_t n = 0;
        int64_t *values = NULL;
        int kind;
        if (noshi_json_kind(column) != NOSHI_JSON_ARRAY) { status = NOSHI_E_MALFORMED; break; }
        id = noshi_json_string(noshi_json_first(column), NULL);
        if (!id) { status = NOSHI_E_MALFORMED; break; }
        status = read_values(column, &n, &values);
        if (status != NOSHI_OK) break;
        if (!strcmp(id, x_id)) {
            if (chart->x) status = NOSHI_E_MALFORMED;
            else { chart->x = values; chart->points = n; values = NULL; }
            free(values);
            continue;
        }
        kind_text = member_text(types, id, NULL);
        kind = kind_text ? kind_of(kind_text) : 0;
        if (!kind || chart->line_count >= NOSHI_CHART_LINES_MAX) {
            free(values);
            status = kind ? NOSHI_E_LIMIT : NOSHI_E_MALFORMED;
            break;
        }
        line_points[chart->line_count] = n;
        chart->lines[chart->line_count].y = values;
        chart->lines[chart->line_count].kind = (uint8_t)kind;
        chart->lines[chart->line_count].color = read_color(colors, id);
        name = member_text(names, id, &name_len);
        snprintf(chart->lines[chart->line_count].name, sizeof(chart->lines[0].name), "%s", name && name_len ? name : id);
        ++chart->line_count;
    }
    if (status == NOSHI_OK && (!chart->x || !chart->line_count)) status = NOSHI_E_MALFORMED;
    /* a series that is shorter or longer than the time axis would be read past its end */
    for (i = 0; status == NOSHI_OK && i < chart->line_count; ++i) {
        if (line_points[i] != chart->points) status = NOSHI_E_MALFORMED;
    }
    if (status == NOSHI_OK) {
        chart->stacked = member_flag(root, "stacked") ? 1 : 0;
        chart->percentage = member_flag(root, "percentage") ? 1 : 0;
    }
    noshi_json_free(doc);
    if (status != NOSHI_OK) {
        noshi_chart_free(chart);
        return status;
    }
    *out = chart;
    return NOSHI_OK;
}

void noshi_stats_graph_free(noshi_stats_graph *graph) {
    if (!graph) return;
    noshi_chart_free(graph->chart);
    memset(graph, 0, sizeof(*graph));
}

static noshi_status copy_text(const noshi_tl_value *value, const char *field, char *out, size_t capacity) {
    const uint8_t *data;
    size_t len;
    if (noshi_tl_get_bytes(value, field, &data, &len) != NOSHI_OK || !data || len >= capacity || memchr(data, 0, len)) return NOSHI_E_MALFORMED;
    memcpy(out, data, len);
    out[len] = 0;
    return NOSHI_OK;
}

noshi_status noshi_stats_graph_read(const noshi_tl_value *value, noshi_stats_graph *out) {
    if (!out) return NOSHI_E_ARG;
    memset(out, 0, sizeof(*out));
    if (noshi_tl_is(value, NOSHI_TL_ID_statsGraphAsync)) {
        if (copy_text(value, "token", out->token, sizeof(out->token)) != NOSHI_OK || !out->token[0]) {
            memset(out, 0, sizeof(*out));
            return NOSHI_E_MALFORMED;
        }
        out->kind = NOSHI_GRAPH_ASYNC;
        return NOSHI_OK;
    }
    if (noshi_tl_is(value, NOSHI_TL_ID_statsGraphError)) {
        if (copy_text(value, "error", out->error, sizeof(out->error)) != NOSHI_OK) {
            memset(out, 0, sizeof(*out));
            return NOSHI_E_MALFORMED;
        }
        out->kind = NOSHI_GRAPH_ERROR;
        return NOSHI_OK;
    }
    if (noshi_tl_is(value, NOSHI_TL_ID_statsGraph)) {
        const noshi_tl_value *json = noshi_tl_get(value, "json");
        const uint8_t *data;
        size_t len;
        noshi_status status;
        if (!noshi_tl_is(json, NOSHI_TL_ID_dataJSON) || noshi_tl_get_bytes(json, "data", &data, &len) != NOSHI_OK || !data) return NOSHI_E_MALFORMED;
        if (noshi_tl_has(value, "zoom_token") && copy_text(value, "zoom_token", out->zoom_token, sizeof(out->zoom_token)) != NOSHI_OK) {
            memset(out, 0, sizeof(*out));
            return NOSHI_E_MALFORMED;
        }
        status = noshi_chart_parse((const char *)data, len, &out->chart);
        if (status != NOSHI_OK) {
            memset(out, 0, sizeof(*out));
            return status;
        }
        out->kind = NOSHI_GRAPH_JSON;
        return NOSHI_OK;
    }
    return NOSHI_E_MALFORMED;
}

noshi_status noshi_channel_stats_read(const noshi_tl_value *answer, int32_t *stats_dc, int *can_view) {
    const noshi_tl_value *full;
    if (!stats_dc || !can_view) return NOSHI_E_ARG;
    *stats_dc = 0;
    *can_view = 0;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_messages_chatFull)) return NOSHI_E_MALFORMED;
    full = noshi_tl_get(answer, "full_chat");
    if (!noshi_tl_is(full, NOSHI_TL_ID_channelFull)) return NOSHI_E_MALFORMED;
    *can_view = noshi_tl_has(full, "can_view_stats") ? 1 : 0;
    if (noshi_tl_has(full, "stats_dc")) {
        if (noshi_tl_get_i32(full, "stats_dc", stats_dc) != NOSHI_OK || *stats_dc <= 0) {
            *stats_dc = 0;
            *can_view = 0;
            return NOSHI_E_MALFORMED;
        }
    }
    return NOSHI_OK;
}

static noshi_status input_channel(noshi_arena *arena, const noshi_peer_ref *peer, noshi_tl_value **out) {
    noshi_tl_value *channel;
    noshi_status status;
    if (!peer || peer->kind != 3 || peer->id <= 0) return NOSHI_E_ARG;
    channel = noshi_tl_new_obj(arena, "inputChannel");
    if (!channel) return NOSHI_E_NOMEM;
    status = noshi_tl_set_i64(arena, channel, "channel_id", peer->id);
    if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "access_hash", peer->access_hash);
    if (status == NOSHI_OK) *out = channel;
    return status;
}

noshi_status noshi_message_stats_request(noshi_arena *arena, const noshi_peer_ref *channel, int32_t message_id, noshi_tl_value **out) {
    noshi_tl_value *request, *input = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || message_id <= 0) return NOSHI_E_ARG;
    status = input_channel(arena, channel, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "stats.getMessageStats");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "channel", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "msg_id", message_id);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_message_stats_read(const noshi_tl_value *answer, noshi_stats_graph *views, noshi_stats_graph *reactions) {
    noshi_status status;
    if (!views || !reactions) return NOSHI_E_ARG;
    memset(views, 0, sizeof(*views));
    memset(reactions, 0, sizeof(*reactions));
    if (!noshi_tl_is(answer, NOSHI_TL_ID_stats_messageStats)) return NOSHI_E_MALFORMED;
    status = noshi_stats_graph_read(noshi_tl_get(answer, "views_graph"), views);
    if (status != NOSHI_OK) return status;
    status = noshi_stats_graph_read(noshi_tl_get(answer, "reactions_by_emotion_graph"), reactions);
    if (status != NOSHI_OK) noshi_stats_graph_free(views);
    return status;
}

noshi_status noshi_async_graph_request(noshi_arena *arena, const char *token, int with_x, int64_t x, noshi_tl_value **out) {
    noshi_tl_value *request;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || !token || !token[0] || strlen(token) >= NOSHI_STATS_TOKEN_MAX) return NOSHI_E_ARG;
    request = noshi_tl_new_obj(arena, "stats.loadAsyncGraph");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set_str(arena, request, "token", token);
    if (status == NOSHI_OK && with_x) status = noshi_tl_set_i64(arena, request, "x", x);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_async_graph_read(const noshi_tl_value *answer, noshi_stats_graph *out) {
    return noshi_stats_graph_read(answer, out);
}

noshi_status noshi_public_forwards_request(noshi_arena *arena, const noshi_peer_ref *channel, int32_t message_id,
                                               const char *offset, noshi_tl_value **out) {
    noshi_tl_value *request, *input = NULL;
    noshi_status status;
    if (out) *out = NULL;
    if (!arena || !out || message_id <= 0 || (offset && strlen(offset) >= NOSHI_STATS_OFFSET_MAX)) return NOSHI_E_ARG;
    status = input_channel(arena, channel, &input);
    if (status != NOSHI_OK) return status;
    request = noshi_tl_new_obj(arena, "stats.getMessagePublicForwards");
    if (!request) return NOSHI_E_NOMEM;
    status = noshi_tl_set(request, "channel", input);
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "msg_id", message_id);
    if (status == NOSHI_OK) status = noshi_tl_set_str(arena, request, "offset", offset ? offset : "");
    if (status == NOSHI_OK) status = noshi_tl_set_i32(arena, request, "limit", NOSHI_PUBLIC_FORWARDS_PAGE);
    if (status == NOSHI_OK) *out = request;
    return status;
}

noshi_status noshi_public_forwards_parse(const noshi_tl_value *answer, noshi_public_forward *rows, size_t capacity, size_t *count,
                                             int32_t *total, char *next, size_t next_capacity) {
    const noshi_tl_value *items;
    uint32_t i;
    size_t n = 0;
    if (count) *count = 0;
    if (total) *total = 0;
    if (next && next_capacity) next[0] = 0;
    if (!rows || !capacity || !count || !total || !next || !next_capacity) return NOSHI_E_ARG;
    if (!noshi_tl_is(answer, NOSHI_TL_ID_stats_publicForwards) || noshi_tl_get_vec(answer, "forwards", &items) != NOSHI_OK) return NOSHI_E_MALFORMED;
    if (items->u.vec.count > capacity || items->u.vec.count > NOSHI_PUBLIC_FORWARDS_PAGE) return NOSHI_E_LIMIT;
    if (noshi_tl_has(answer, "next_offset") &&
        (copy_text(answer, "next_offset", next, next_capacity) != NOSHI_OK || strlen(next) >= NOSHI_STATS_OFFSET_MAX)) {
        next[0] = 0;
        return NOSHI_E_MALFORMED;
    }
    for (i = 0; i < items->u.vec.count; ++i) {
        const noshi_tl_value *item = items->u.vec.items[i], *inner;
        noshi_public_forward row;
        noshi_peer peer;
        memset(&row, 0, sizeof(row));
        if (noshi_tl_is(item, NOSHI_TL_ID_publicForwardMessage)) {
            inner = noshi_tl_get(item, "message");
            /* a deleted or inaccessible message arrives empty; there is nothing to show of it */
            if (!noshi_tl_is(inner, NOSHI_TL_ID_message)) continue;
            if (noshi_peer_from_tl(noshi_tl_get(inner, "peer_id"), &peer) != NOSHI_OK || peer.id <= 0 ||
                noshi_tl_get_i32(inner, "id", &row.item_id) != NOSHI_OK || row.item_id <= 0 ||
                noshi_tl_get_i32(inner, "date", &row.date) != NOSHI_OK || row.date < 0) {
                next[0] = 0;
                return NOSHI_E_MALFORMED;
            }
            if (noshi_tl_has(inner, "views") && (noshi_tl_get_i32(inner, "views", &row.views) != NOSHI_OK || row.views < 0)) {
                next[0] = 0;
                return NOSHI_E_MALFORMED;
            }
        } else if (noshi_tl_is(item, NOSHI_TL_ID_publicForwardStory)) {
            inner = noshi_tl_get(item, "story");
            if (!noshi_tl_is(inner, NOSHI_TL_ID_storyItem)) continue;
            if (noshi_peer_from_tl(noshi_tl_get(item, "peer"), &peer) != NOSHI_OK || peer.id <= 0 ||
                noshi_tl_get_i32(inner, "id", &row.item_id) != NOSHI_OK || row.item_id <= 0 ||
                noshi_tl_get_i32(inner, "date", &row.date) != NOSHI_OK || row.date < 0) {
                next[0] = 0;
                return NOSHI_E_MALFORMED;
            }
            row.story = 1;
            if (noshi_tl_has(inner, "views")) {
                const noshi_tl_value *views = noshi_tl_get(inner, "views");
                if (noshi_tl_has(views, "views_count") && (noshi_tl_get_i32(views, "views_count", &row.views) != NOSHI_OK || row.views < 0)) {
                    next[0] = 0;
                    return NOSHI_E_MALFORMED;
                }
            }
        } else {
            continue;
        }
        row.peer_kind = peer.kind;
        row.peer_id = peer.id;
        rows[n++] = row;
    }
    *count = n;
    if (noshi_tl_get_i32(answer, "count", total) != NOSHI_OK || *total < (int32_t)n) *total = (int32_t)n;
    return NOSHI_OK;
}

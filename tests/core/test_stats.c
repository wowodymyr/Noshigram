#include <stdio.h>
#include <string.h>

#include "noshi_stats.h"
#include "noshi_tl_ids.h"
#include "test_util.h"

static noshi_arena arena;

static noshi_tl_value *obj(const char *name) {
    noshi_tl_value *v = noshi_tl_new_obj(&arena, name);
    CHECK(v != NULL);
    return v;
}
static void set(noshi_tl_value *v, const char *field, noshi_tl_value *x) { CHECK_EQ_INT(noshi_tl_set(v, field, x), NOSHI_OK); }
static void i32(noshi_tl_value *v, const char *field, int32_t x) { CHECK_EQ_INT(noshi_tl_set_i32(&arena, v, field, x), NOSHI_OK); }
static void i64(noshi_tl_value *v, const char *field, int64_t x) { CHECK_EQ_INT(noshi_tl_set_i64(&arena, v, field, x), NOSHI_OK); }
static void str(noshi_tl_value *v, const char *field, const char *x) { CHECK_EQ_INT(noshi_tl_set_str(&arena, v, field, x), NOSHI_OK); }

static const char GOOD[] =
    "{\"columns\":[[\"x\",1700000000000,1700086400000,1700172800000],[\"y0\",10,20,30],[\"y1\",1,2,3]],"
    "\"types\":{\"y0\":\"line\",\"y1\":\"bar\",\"x\":\"x\"},\"names\":{\"y0\":\"Views\",\"y1\":\"Shares\"},"
    "\"colors\":{\"y0\":\"#3497ED\",\"y1\":\"#33c27f\"},\"stacked\":true}";

static noshi_status parse(const char *text, noshi_chart **out) { return noshi_chart_parse(text, strlen(text), out); }

static void test_chart(void) {
    noshi_chart *chart = NULL;
    CHECK_EQ_INT(parse(GOOD, &chart), NOSHI_OK);
    CHECK(chart != NULL);
    if (chart) {
        CHECK_EQ_INT(chart->points, 3);
        CHECK_EQ_INT(chart->line_count, 2);
        CHECK_EQ_INT(chart->x[2], 1700172800000LL);
        CHECK_EQ_INT(chart->lines[0].y[1], 20);
        CHECK_EQ_INT(chart->lines[0].kind, NOSHI_CHART_LINE);
        CHECK_EQ_INT(chart->lines[1].kind, NOSHI_CHART_BAR);
        CHECK_EQ_INT(chart->lines[0].color, 0x3497EDu);
        CHECK_EQ_INT(chart->lines[1].color, 0x33C27Fu);
        CHECK(!strcmp(chart->lines[1].name, "Shares"));
        CHECK_EQ_INT(chart->stacked, 1);
        CHECK_EQ_INT(chart->percentage, 0);
    }
    noshi_chart_free(chart);

    /* the x column may come last and have another id; a missing name falls back to the id, a bad color to gray */
    CHECK_EQ_INT(parse("{\"columns\":[[\"y0\",5,6],[\"t\",1,2]],\"types\":{\"y0\":\"area\",\"t\":\"x\"},\"colors\":{\"y0\":\"red\"}}", &chart), NOSHI_OK);
    if (chart) {
        CHECK_EQ_INT(chart->points, 2);
        CHECK(!strcmp(chart->lines[0].name, "y0"));
        CHECK_EQ_INT(chart->lines[0].color, 0x8e8e93u);
        CHECK_EQ_INT(chart->lines[0].kind, NOSHI_CHART_AREA);
    }
    noshi_chart_free(chart);

    /* what is not a chart is malformed and leaves nothing behind */
    CHECK_EQ_INT(parse("{}", &chart), NOSHI_E_MALFORMED);
    CHECK(chart == NULL);
    CHECK_EQ_INT(parse("not json", &chart), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"columns\":[[\"x\",1,2],[\"y0\",1]],\"types\":{\"y0\":\"line\",\"x\":\"x\"}}", &chart), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"columns\":[[\"y0\",1],[\"x\",1,2]],\"types\":{\"y0\":\"line\",\"x\":\"x\"}}", &chart), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"columns\":[[\"x\",1,2],[\"y0\",1,2]],\"types\":{\"y0\":\"pie\",\"x\":\"x\"}}", &chart), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"columns\":[[\"x\",1,2],[\"y0\",1,2]],\"types\":{\"x\":\"x\"}}", &chart), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"columns\":[[\"x\",1,2],[\"y0\",1.5,2]],\"types\":{\"y0\":\"line\",\"x\":\"x\"}}", &chart), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"columns\":[[\"x\",1,2]],\"types\":{\"x\":\"x\"}}", &chart), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"columns\":[[\"x\"],[\"y0\"]],\"types\":{\"y0\":\"line\",\"x\":\"x\"}}", &chart), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(parse("{\"columns\":[[\"x\",1],[\"x\",2],[\"y0\",1]],\"types\":{\"y0\":\"line\",\"x\":\"x\"}}", &chart), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_chart_parse(NULL, 0, &chart), NOSHI_E_ARG);
    CHECK_EQ_INT(noshi_chart_parse("{}", 2, NULL), NOSHI_E_ARG);
}

static void test_chart_limits(void) {
    static char text[40000];
    noshi_chart *chart = NULL;
    size_t len;
    unsigned i, n;
    /* the most points the chart takes, and one more */
    for (n = NOSHI_CHART_POINTS_MAX; n <= NOSHI_CHART_POINTS_MAX + 1; ++n) {
        len = (size_t)snprintf(text, sizeof(text), "{\"columns\":[[\"x\"");
        for (i = 0; i < n; ++i) len += (size_t)snprintf(text + len, sizeof(text) - len, ",%u", i);
        len += (size_t)snprintf(text + len, sizeof(text) - len, "],[\"y0\"");
        for (i = 0; i < n; ++i) len += (size_t)snprintf(text + len, sizeof(text) - len, ",1");
        len += (size_t)snprintf(text + len, sizeof(text) - len, "]],\"types\":{\"y0\":\"line\",\"x\":\"x\"}}");
        {
            noshi_status status = noshi_chart_parse(text, len, &chart);
            /* the JSON reader caps the number of values below the point cap, so a full chart ends in a limit either way and never in a crash */
            CHECK(status == NOSHI_OK || status == NOSHI_E_LIMIT || status == NOSHI_E_MALFORMED);
            CHECK((status == NOSHI_OK) == (chart != NULL));
            if (n > NOSHI_CHART_POINTS_MAX) CHECK(status != NOSHI_OK);
            noshi_chart_free(chart);
            chart = NULL;
        }
    }
    /* more series than the chart holds */
    len = (size_t)snprintf(text, sizeof(text), "{\"columns\":[[\"x\",1,2]");
    for (i = 0; i < NOSHI_CHART_LINES_MAX + 1; ++i) len += (size_t)snprintf(text + len, sizeof(text) - len, ",[\"y%u\",1,2]", i);
    len += (size_t)snprintf(text + len, sizeof(text) - len, "],\"types\":{\"x\":\"x\"");
    for (i = 0; i < NOSHI_CHART_LINES_MAX + 1; ++i) len += (size_t)snprintf(text + len, sizeof(text) - len, ",\"y%u\":\"line\"", i);
    len += (size_t)snprintf(text + len, sizeof(text) - len, "}}");
    CHECK_EQ_INT(noshi_chart_parse(text, len, &chart), NOSHI_E_LIMIT);
    CHECK(chart == NULL);
}

static noshi_tl_value *graph_json(const char *json, const char *zoom) {
    noshi_tl_value *graph = obj("statsGraph"), *data = obj("dataJSON");
    str(data, "data", json);
    set(graph, "json", data);
    if (zoom) str(graph, "zoom_token", zoom);
    return graph;
}

static void test_graph_and_answer(void) {
    noshi_stats_graph a, b;
    noshi_tl_value *answer = obj("stats.messageStats"), *node;
    CHECK_EQ_INT(noshi_stats_graph_read(graph_json(GOOD, "zoom1"), &a), NOSHI_OK);
    CHECK_EQ_INT(a.kind, NOSHI_GRAPH_JSON);
    CHECK(a.chart != NULL);
    CHECK(!strcmp(a.zoom_token, "zoom1"));
    noshi_stats_graph_free(&a);
    CHECK(a.chart == NULL);
    CHECK_EQ_INT(a.kind, NOSHI_GRAPH_NONE);

    node = obj("statsGraphAsync");
    str(node, "token", "tok");
    CHECK_EQ_INT(noshi_stats_graph_read(node, &a), NOSHI_OK);
    CHECK_EQ_INT(a.kind, NOSHI_GRAPH_ASYNC);
    CHECK(!strcmp(a.token, "tok"));
    node = obj("statsGraphAsync");
    str(node, "token", "");
    CHECK_EQ_INT(noshi_stats_graph_read(node, &a), NOSHI_E_MALFORMED);

    node = obj("statsGraphError");
    str(node, "error", "not enough data");
    CHECK_EQ_INT(noshi_stats_graph_read(node, &a), NOSHI_OK);
    CHECK_EQ_INT(a.kind, NOSHI_GRAPH_ERROR);
    CHECK(!strcmp(a.error, "not enough data"));

    CHECK_EQ_INT(noshi_stats_graph_read(graph_json("{}", NULL), &a), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(a.kind, NOSHI_GRAPH_NONE);
    CHECK_EQ_INT(noshi_stats_graph_read(obj("inputChannelEmpty"), &a), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_stats_graph_read(NULL, &a), NOSHI_E_MALFORMED);

    set(answer, "views_graph", graph_json(GOOD, NULL));
    node = obj("statsGraphAsync");
    str(node, "token", "emotions");
    set(answer, "reactions_by_emotion_graph", node);
    CHECK_EQ_INT(noshi_message_stats_read(answer, &a, &b), NOSHI_OK);
    CHECK_EQ_INT(a.kind, NOSHI_GRAPH_JSON);
    CHECK_EQ_INT(b.kind, NOSHI_GRAPH_ASYNC);
    noshi_stats_graph_free(&a);
    noshi_stats_graph_free(&b);

    /* a bad second graph must not leak the first */
    answer = obj("stats.messageStats");
    set(answer, "views_graph", graph_json(GOOD, NULL));
    set(answer, "reactions_by_emotion_graph", graph_json("{}", NULL));
    CHECK_EQ_INT(noshi_message_stats_read(answer, &a, &b), NOSHI_E_MALFORMED);
    CHECK(a.chart == NULL && b.chart == NULL);
    CHECK_EQ_INT(noshi_message_stats_read(obj("messages.messageReactionsList"), &a, &b), NOSHI_E_MALFORMED);
}

static void test_requests(void) {
    noshi_peer_ref channel = {3, 777, 888, 0, 0};
    noshi_peer_ref chat = {2, 5, 0, 0, 0};
    noshi_tl_value *request = NULL, *input;
    int64_t id = 0;
    CHECK_EQ_INT(noshi_message_stats_request(&arena, &channel, 42, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_stats_getMessageStats);
    input = (noshi_tl_value *)noshi_tl_get(request, "channel");
    CHECK(noshi_tl_is(input, NOSHI_TL_ID_inputChannel));
    CHECK_EQ_INT(noshi_tl_get_i64(input, "channel_id", &id), NOSHI_OK);
    CHECK_EQ_INT(id, 777);
    CHECK_EQ_INT(noshi_tl_get_i64(input, "access_hash", &id), NOSHI_OK);
    CHECK_EQ_INT(id, 888);
    CHECK_EQ_INT(noshi_message_stats_request(&arena, &channel, 0, &request), NOSHI_E_ARG);
    CHECK(request == NULL);
    CHECK_EQ_INT(noshi_message_stats_request(&arena, &chat, 42, &request), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_async_graph_request(&arena, "tok", 1, 1700000000000LL, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_stats_loadAsyncGraph);
    CHECK(noshi_tl_has(request, "x"));
    CHECK_EQ_INT(noshi_tl_get_i64(request, "x", &id), NOSHI_OK);
    CHECK_EQ_INT(id, 1700000000000LL);
    CHECK_EQ_INT(noshi_async_graph_request(&arena, "tok", 0, 0, &request), NOSHI_OK);
    CHECK(!noshi_tl_has(request, "x"));
    CHECK_EQ_INT(noshi_async_graph_request(&arena, "", 0, 0, &request), NOSHI_E_ARG);

    CHECK_EQ_INT(noshi_public_forwards_request(&arena, &channel, 42, NULL, &request), NOSHI_OK);
    CHECK_EQ_INT(noshi_tl_id(request), NOSHI_TL_ID_stats_getMessagePublicForwards);
    CHECK_EQ_INT(noshi_public_forwards_request(&arena, &channel, 42, "abc", &request), NOSHI_OK);
    {
        char long_offset[NOSHI_STATS_OFFSET_MAX + 1];
        memset(long_offset, 'a', sizeof(long_offset) - 1);
        long_offset[sizeof(long_offset) - 1] = 0;
        CHECK_EQ_INT(noshi_public_forwards_request(&arena, &channel, 42, long_offset, &request), NOSHI_E_ARG);
    }
}

static void test_channel_stats(void) {
    noshi_tl_value *answer = obj("messages.chatFull"), *full = obj("channelFull");
    int32_t dc = -1;
    int can = -1;
    i32(full, "stats_dc", 4);
    CHECK_EQ_INT(noshi_tl_set_flag(full, "can_view_stats"), NOSHI_OK);
    set(answer, "full_chat", full);
    CHECK_EQ_INT(noshi_channel_stats_read(answer, &dc, &can), NOSHI_OK);
    CHECK_EQ_INT(dc, 4);
    CHECK_EQ_INT(can, 1);

    answer = obj("messages.chatFull");
    full = obj("channelFull");
    set(answer, "full_chat", full);
    CHECK_EQ_INT(noshi_channel_stats_read(answer, &dc, &can), NOSHI_OK);
    CHECK_EQ_INT(dc, 0);
    CHECK_EQ_INT(can, 0);

    answer = obj("messages.chatFull");
    full = obj("channelFull");
    i32(full, "stats_dc", 0);
    set(answer, "full_chat", full);
    CHECK_EQ_INT(noshi_channel_stats_read(answer, &dc, &can), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(can, 0);
    answer = obj("messages.chatFull");
    set(answer, "full_chat", obj("chatFull"));
    CHECK_EQ_INT(noshi_channel_stats_read(answer, &dc, &can), NOSHI_E_MALFORMED);
}

static noshi_tl_value *peer_channel(int64_t id) {
    noshi_tl_value *peer = obj("peerChannel");
    i64(peer, "channel_id", id);
    return peer;
}

static void test_public_forwards(void) {
    noshi_tl_value *answer = obj("stats.publicForwards"), *vec = noshi_tl_new_vec(&arena, 4), *item, *message, *story, *views;
    noshi_public_forward rows[NOSHI_PUBLIC_FORWARDS_PAGE];
    size_t count = 99;
    int32_t total = 0;
    char next[NOSHI_STATS_OFFSET_MAX];

    item = obj("publicForwardMessage");
    message = obj("message");
    set(message, "peer_id", peer_channel(50));
    i32(message, "id", 7);
    i32(message, "date", 1700000000);
    i32(message, "views", 1234);
    set(item, "message", message);
    CHECK_EQ_INT(noshi_tl_vec_set(vec, 0, item), NOSHI_OK);

    /* a message the server could not give is skipped */
    item = obj("publicForwardMessage");
    set(item, "message", obj("messageEmpty"));
    CHECK_EQ_INT(noshi_tl_vec_set(vec, 1, item), NOSHI_OK);

    item = obj("publicForwardStory");
    story = obj("storyItem");
    i32(story, "id", 3);
    i32(story, "date", 1700000100);
    views = obj("storyViews");
    i32(views, "views_count", 55);
    set(story, "views", views);
    set(item, "peer", peer_channel(60));
    set(item, "story", story);
    CHECK_EQ_INT(noshi_tl_vec_set(vec, 2, item), NOSHI_OK);

    item = obj("publicForwardMessage");
    message = obj("message");
    set(message, "peer_id", peer_channel(70));
    i32(message, "id", 9);
    i32(message, "date", 1700000200);
    set(item, "message", message);
    CHECK_EQ_INT(noshi_tl_vec_set(vec, 3, item), NOSHI_OK);

    set(answer, "forwards", vec);
    i32(answer, "count", 120);
    str(answer, "next_offset", "page2");
    CHECK_EQ_INT(noshi_public_forwards_parse(answer, rows, NOSHI_PUBLIC_FORWARDS_PAGE, &count, &total, next, sizeof(next)), NOSHI_OK);
    CHECK_EQ_INT(count, 3);
    CHECK_EQ_INT(total, 120);
    CHECK(!strcmp(next, "page2"));
    CHECK_EQ_INT(rows[0].story, 0);
    CHECK_EQ_INT(rows[0].peer_kind, 3);
    CHECK_EQ_INT(rows[0].peer_id, 50);
    CHECK_EQ_INT(rows[0].item_id, 7);
    CHECK_EQ_INT(rows[0].views, 1234);
    CHECK_EQ_INT(rows[1].story, 1);
    CHECK_EQ_INT(rows[1].peer_id, 60);
    CHECK_EQ_INT(rows[1].views, 55);
    CHECK_EQ_INT(rows[2].views, 0);

    /* a page larger than the buffer is a limit, not a truncation */
    CHECK_EQ_INT(noshi_public_forwards_parse(answer, rows, 2, &count, &total, next, sizeof(next)), NOSHI_E_LIMIT);
    CHECK_EQ_INT(count, 0);
    CHECK_EQ_INT(next[0], 0);

    /* a count below the rows is raised to them; no next offset is an empty one */
    answer = obj("stats.publicForwards");
    vec = noshi_tl_new_vec(&arena, 1);
    item = obj("publicForwardMessage");
    message = obj("message");
    set(message, "peer_id", peer_channel(50));
    i32(message, "id", 7);
    i32(message, "date", 1);
    set(item, "message", message);
    CHECK_EQ_INT(noshi_tl_vec_set(vec, 0, item), NOSHI_OK);
    set(answer, "forwards", vec);
    i32(answer, "count", 0);
    CHECK_EQ_INT(noshi_public_forwards_parse(answer, rows, NOSHI_PUBLIC_FORWARDS_PAGE, &count, &total, next, sizeof(next)), NOSHI_OK);
    CHECK_EQ_INT(total, 1);
    CHECK_EQ_INT(next[0], 0);

    /* a message without a usable id is malformed */
    answer = obj("stats.publicForwards");
    vec = noshi_tl_new_vec(&arena, 1);
    item = obj("publicForwardMessage");
    message = obj("message");
    set(message, "peer_id", peer_channel(50));
    i32(message, "id", 0);
    i32(message, "date", 1);
    set(item, "message", message);
    CHECK_EQ_INT(noshi_tl_vec_set(vec, 0, item), NOSHI_OK);
    set(answer, "forwards", vec);
    CHECK_EQ_INT(noshi_public_forwards_parse(answer, rows, NOSHI_PUBLIC_FORWARDS_PAGE, &count, &total, next, sizeof(next)), NOSHI_E_MALFORMED);
    CHECK_EQ_INT(noshi_public_forwards_parse(obj("messages.messageReactionsList"), rows, NOSHI_PUBLIC_FORWARDS_PAGE, &count, &total, next, sizeof(next)), NOSHI_E_MALFORMED);
}

int main(void) {
    noshi_arena_init(&arena, 4u * 1024u * 1024u);
    test_chart();
    test_chart_limits();
    test_graph_and_answer();
    test_requests();
    test_channel_stats();
    test_public_forwards();
    noshi_arena_free(&arena);
    return test_finish("test_stats");
}

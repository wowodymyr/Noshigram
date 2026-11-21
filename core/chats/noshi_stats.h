#ifndef NOSHI_STATS_H
#define NOSHI_STATS_H

#include <stddef.h>
#include <stdint.h>

#include "noshi_messages.h"
#include "noshi_tl.h"

/* the statistics of one channel post: two graphs and the public channels that forwarded it. The graphs come as JSON
   text from the server (its own chart format), so every size below is a hard cap on what a hostile or broken answer
   can make the app allocate */

#define NOSHI_CHART_POINTS_MAX 1024
#define NOSHI_CHART_LINES_MAX 16
#define NOSHI_CHART_NAME_MAX 64
#define NOSHI_STATS_TOKEN_MAX 256
#define NOSHI_STATS_ERROR_MAX 160
#define NOSHI_PUBLIC_FORWARDS_PAGE 30
#define NOSHI_STATS_OFFSET_MAX 256

typedef enum noshi_chart_kind {
    NOSHI_CHART_LINE = 1,
    NOSHI_CHART_BAR,
    NOSHI_CHART_AREA,
    NOSHI_CHART_STEP
} noshi_chart_kind;

typedef struct noshi_chart_line {
    char name[NOSHI_CHART_NAME_MAX];
    uint32_t color;         /* 0xRRGGBB */
    uint8_t kind;           /* noshi_chart_kind */
    int64_t *y;             /* chart.points values */
} noshi_chart_line;

/* one chart: x holds unix milliseconds, each line one value per x */
typedef struct noshi_chart {
    uint32_t points;
    uint32_t line_count;
    int64_t *x;
    noshi_chart_line lines[NOSHI_CHART_LINES_MAX];
    uint8_t stacked;        /* the lines add up to the height of the bar */
    uint8_t percentage;     /* the lines are shares of a whole */
} noshi_chart;

/* parses the JSON a statsGraph carries; NOSHI_E_MALFORMED for a document that is not a chart this reader knows, NOSHI_E_LIMIT for one
   past the caps above. *out is NULL unless the answer is NOSHI_OK, and then it is owned by the caller */
noshi_status noshi_chart_parse(const char *json, size_t len, noshi_chart **out);
void noshi_chart_free(noshi_chart *chart);

typedef enum noshi_graph_kind {
    NOSHI_GRAPH_NONE = 0,
    NOSHI_GRAPH_JSON,     /* chart is set; zoom_token, when not empty, loads the same range at a finer step */
    NOSHI_GRAPH_ASYNC,    /* token loads the graph with stats.loadAsyncGraph */
    NOSHI_GRAPH_ERROR     /* the server says why it has no graph */
} noshi_graph_kind;

typedef struct noshi_stats_graph {
    noshi_graph_kind kind;
    noshi_chart *chart;
    char token[NOSHI_STATS_TOKEN_MAX];
    char zoom_token[NOSHI_STATS_TOKEN_MAX];
    char error[NOSHI_STATS_ERROR_MAX];
} noshi_stats_graph;

void noshi_stats_graph_free(noshi_stats_graph *graph);
/* one StatsGraph object; out is always initialised */
noshi_status noshi_stats_graph_read(const noshi_tl_value *value, noshi_stats_graph *out);

/* channels.getFullChannel's answer: the data center that keeps the statistics (zero when the answer names none) and whether the
   account may read them */
noshi_status noshi_channel_stats_read(const noshi_tl_value *answer, int32_t *stats_dc, int *can_view);

/* stats.getMessageStats for a post of a channel; peer must be a channel with its access hash */
noshi_status noshi_message_stats_request(noshi_arena *arena, const noshi_peer_ref *channel, int32_t message_id, noshi_tl_value **out);
/* a stats.messageStats: the graph of views and shares, and the graph of reactions by emotion */
noshi_status noshi_message_stats_read(const noshi_tl_value *answer, noshi_stats_graph *views, noshi_stats_graph *reactions);
/* stats.loadAsyncGraph; with_x asks for the finer step around the x (milliseconds) of a zoom token */
noshi_status noshi_async_graph_request(noshi_arena *arena, const char *token, int with_x, int64_t x, noshi_tl_value **out);
/* the StatsGraph of the answer; NOSHI_E_MALFORMED for anything else */
noshi_status noshi_async_graph_read(const noshi_tl_value *answer, noshi_stats_graph *out);

typedef struct noshi_public_forward {
    uint8_t story;          /* a story of the channel, not a post */
    int32_t peer_kind;      /* where it was forwarded to, as noshi_peer */
    int64_t peer_id;
    int32_t item_id;        /* the message or story id there */
    int32_t date;           /* unix seconds */
    int32_t views;          /* zero when the server counts none */
} noshi_public_forward;

noshi_status noshi_public_forwards_request(noshi_arena *arena, const noshi_peer_ref *channel, int32_t message_id,
                                               const char *offset, noshi_tl_value **out);
/* the rows of a stats.publicForwards page, at most capacity of them; total is its count field (at least the rows), next the offset of the
   following page, empty at the end. an entry that is neither a message nor a story is skipped */
noshi_status noshi_public_forwards_parse(const noshi_tl_value *answer, noshi_public_forward *rows, size_t capacity, size_t *count,
                                             int32_t *total, char *next, size_t next_capacity);

#endif

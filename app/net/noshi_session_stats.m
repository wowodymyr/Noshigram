#import "noshi_session_internal.h"

#import "noshi_rpc.h"
#import "noshi_session_stats.h"

#include <string.h>

@implementation NoshiChartData

@synthesize chart = _chart;

- (id)initWithChart:(noshi_chart *)chart {
    self = [super init];
    if (!self) {
        noshi_chart_free(chart);
        return nil;
    }
    _chart = chart;
    return self;
}

- (void)dealloc {
    noshi_chart_free(_chart);
    [super dealloc];
}

@end

@implementation NoshiStatsGraph

@synthesize kind = _kind;
@synthesize chartData = _chartData;
@synthesize token = _token;
@synthesize zoomToken = _zoomToken;
@synthesize errorText = _errorText;

- (id)initWithGraph:(noshi_stats_graph *)graph {
    self = [super init];
    if (!self) return nil;
    _kind = graph->kind;
    if (graph->chart) {
        _chartData = [[NoshiChartData alloc] initWithChart:graph->chart];
        graph->chart = NULL;
    }
    _token = [[NSString stringWithUTF8String:graph->token] copy];
    _zoomToken = [[NSString stringWithUTF8String:graph->zoom_token] copy];
    _errorText = [[NSString stringWithUTF8String:graph->error] copy];
    return self;
}

- (void)dealloc {
    [_chartData release];
    [_token release];
    [_zoomToken release];
    [_errorText release];
    [super dealloc];
}

@end

/* what the server said of a channel's statistics: the data center and whether this account may read them. asking again costs a getFullChannel, which the server meters hard,
   so a retry, or the next post of the same channel, goes on from what is known; a flood wait is kept until it is over, and a retry before that asks nothing */
static NSMutableDictionary *NoshiStatsKnown(void) {
    static NSMutableDictionary *known;
    if (!known) known = [[NSMutableDictionary alloc] init];
    return known;
}

static NSNumber *NoshiStatsKey(noshi_peer_ref peer) { return [NSNumber numberWithLongLong:peer.id]; }

@interface NoshiSession (StatsPrivate)
- (void)rememberStatsFailure:(NSString *)error key:(NSNumber *)key;
- (void)loadMessageStatsOfMessageId:(int32_t)messageId peer:(noshi_peer_ref)peer key:(NSNumber *)key dc:(int32_t)statsDc
                         completion:(void (^)(NoshiStatsGraph *, NoshiStatsGraph *, int32_t, NSString *))completion;
@end

@implementation NoshiSession (Stats)

- (void)loadStatsOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog
                  completion:(void (^)(NoshiStatsGraph *, NoshiStatsGraph *, int32_t, NSString *))completion {
    void (^done)(NoshiStatsGraph *, NoshiStatsGraph *, int32_t, NSString *) = [completion copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    NSNumber *key = NoshiStatsKey(peer);
    NSDictionary *known;
    @synchronized (NoshiStatsKnown()) { known = [[[NoshiStatsKnown() objectForKey:key] retain] autorelease]; }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval until = [[known objectForKey:@"until"] doubleValue];
    if (until > now) {
        NSString *wait = [NSString stringWithFormat:@"FLOOD_WAIT_%d", (int)ceil(until - now)];
        [self deliverMain:^{ done(nil, nil, 0, wait); [done release]; }];
        return;
    }
    if ([known objectForKey:@"dc"]) {
        int32_t cachedDc = [[known objectForKey:@"dc"] intValue];
        [self loadMessageStatsOfMessageId:messageId peer:peer key:key dc:cachedDc completion:done];
        [done release];
        return;
    }
    /* the full channel names the data center of its statistics, and whether this account may read them */
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        noshi_tl_value *channel = noshi_tl_new_obj(arena, "inputChannel");
        *request = noshi_tl_new_obj(arena, "channels.getFullChannel");
        if (!channel || !*request) return NOSHI_E_NOMEM;
        noshi_status status = noshi_tl_set_i64(arena, channel, "channel_id", peer.id);
        if (status == NOSHI_OK) status = noshi_tl_set_i64(arena, channel, "access_hash", peer.access_hash);
        if (status == NOSHI_OK) status = noshi_tl_set(*request, "channel", channel);
        return status;
    } handler:^(const noshi_mt_rpc_result *info) {
        NSString *error = info->status == NOSHI_OK ? nil : NoshiDownloadErrorName(info);
        int32_t dc = 0;
        int can = 0;
        if (!error) {
            noshi_status status = noshi_channel_stats_read(info->value, &dc, &can);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: channel statistics info rejected: %s", noshi_status_name(status));
                error = @"INTERNAL";
            } else if (!can) {
                error = @"CHAT_ADMIN_REQUIRED";
            }
        }
        if (error) {
            [self noteRpcError:error];
            [self rememberStatsFailure:error key:key];
            NSString *problem = [[error copy] autorelease];
            [self deliverMain:^{ done(nil, nil, 0, problem); [done release]; }];
            return;
        }
        if (dc <= 0) dc = [self workerDc];
        @synchronized (NoshiStatsKnown()) { [NoshiStatsKnown() setObject:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:dc] forKey:@"dc"] forKey:key]; }
        [self loadMessageStatsOfMessageId:messageId peer:peer key:key dc:dc completion:done];
        [done release];
    }];
}

- (void)rememberStatsFailure:(NSString *)error key:(NSNumber *)key {
    if (![error hasPrefix:@"FLOOD_WAIT_"] && ![error hasPrefix:@"FLOOD_PREMIUM_WAIT_"]) return;
    NSRange tail = [error rangeOfString:@"_" options:NSBackwardsSearch];
    int seconds = [[error substringFromIndex:tail.location + 1] intValue];
    if (seconds < 1) return;
    @synchronized (NoshiStatsKnown()) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:[NoshiStatsKnown() objectForKey:key]];
        [entry setObject:[NSNumber numberWithDouble:[NSDate timeIntervalSinceReferenceDate] + seconds] forKey:@"until"];
        [NoshiStatsKnown() setObject:entry forKey:key];
    }
}

/* the statistics of the post itself, asked of the data center the channel names; done is owned by the caller's copy, so it is copied again here */
- (void)loadMessageStatsOfMessageId:(int32_t)messageId peer:(noshi_peer_ref)peer key:(NSNumber *)key dc:(int32_t)statsDc
                         completion:(void (^)(NoshiStatsGraph *, NoshiStatsGraph *, int32_t, NSString *))completion {
    void (^done)(NoshiStatsGraph *, NoshiStatsGraph *, int32_t, NSString *) = [completion copy];
    {
        [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
            return noshi_message_stats_request(arena, &peer, messageId, request);
        } onDc:statsDc handler:^(const noshi_mt_rpc_result *result) {
            /* this runs on the link's thread: the graphs are plain C data until they are wrapped */
            noshi_stats_graph views, reactions;
            NoshiStatsGraph *viewsGraph = nil, *reactionsGraph = nil;
            NSString *failure = result->status == NOSHI_OK ? nil : NoshiDownloadErrorName(result);
            if (failure) [self rememberStatsFailure:failure key:key];
            if (!failure) {
                noshi_status status = noshi_message_stats_read(result->value, &views, &reactions);
                if (status != NOSHI_OK) {
                    NSLog(@"noshigram: message statistics rejected: %s", noshi_status_name(status));
                    failure = status == NOSHI_E_LIMIT ? @"CHART_TOO_LARGE" : @"INTERNAL";
                } else {
                    viewsGraph = [[[NoshiStatsGraph alloc] initWithGraph:&views] autorelease];
                    reactionsGraph = [[[NoshiStatsGraph alloc] initWithGraph:&reactions] autorelease];
                    noshi_stats_graph_free(&views);
                    noshi_stats_graph_free(&reactions);
                }
            }
            NSString *problem = [[failure copy] autorelease];
            [self deliverMain:^{ done(viewsGraph, reactionsGraph, statsDc, problem); [done release]; }];
        }];
    }
}

- (void)loadGraphWithToken:(NSString *)token x:(int64_t)x hasX:(BOOL)hasX dc:(int32_t)dc
                completion:(void (^)(NoshiStatsGraph *, NSString *))completion {
    void (^done)(NoshiStatsGraph *, NSString *) = [completion copy];
    NSString *asked = [token copy];
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_async_graph_request(arena, asked.UTF8String, hasX, x, request);
    } onDc:dc handler:^(const noshi_mt_rpc_result *result) {
        noshi_stats_graph graph;
        NoshiStatsGraph *loaded = nil;
        NSString *failure = result->status == NOSHI_OK ? nil : NoshiDownloadErrorName(result);
        if (!failure) {
            noshi_status status = noshi_async_graph_read(result->value, &graph);
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: graph answer rejected: %s", noshi_status_name(status));
                failure = status == NOSHI_E_LIMIT ? @"CHART_TOO_LARGE" : @"INTERNAL";
            } else {
                loaded = [[[NoshiStatsGraph alloc] initWithGraph:&graph] autorelease];
                noshi_stats_graph_free(&graph);
            }
        }
        NSString *problem = [[failure copy] autorelease];
        [self deliverMain:^{ done(loaded, problem); [done release]; }];
    }];
    [asked release];
}

- (void)loadPublicForwardsOfMessageId:(int32_t)messageId ofDialog:(NoshiDialog *)dialog dc:(int32_t)dc offset:(NSString *)offset
                           completion:(void (^)(NSArray *, NSDictionary *, NSString *, int32_t, NSString *))completion {
    void (^done)(NSArray *, NSDictionary *, NSString *, int32_t, NSString *) = [completion copy];
    NSString *cursor = [offset copy];
    noshi_peer_ref peer = NoshiPeerRefOfDialog(dialog);
    [self invokeBuilt:^noshi_status(noshi_arena *arena, noshi_tl_value **request) {
        return noshi_public_forwards_request(arena, &peer, messageId, cursor.UTF8String, request);
    } onDc:dc handler:^(const noshi_mt_rpc_result *result) {
        NSString *failure = result->status == NOSHI_OK ? nil : NoshiDownloadErrorName(result);
        NSMutableArray *items = nil;
        NSDictionary *people = nil;
        NSString *next = nil;
        int32_t total = 0;
        if (!failure) {
            noshi_public_forward rows[NOSHI_PUBLIC_FORWARDS_PAGE];
            size_t count = 0;
            char nextOffset[NOSHI_STATS_OFFSET_MAX];
            noshi_status status = noshi_public_forwards_parse(result->value, rows, NOSHI_PUBLIC_FORWARDS_PAGE, &count, &total, nextOffset, sizeof(nextOffset));
            /* a next page that is the one just read, or that follows an empty one, would be asked for forever */
            if (status == NOSHI_OK && nextOffset[0] && (!count || (cursor && !strcmp(cursor.UTF8String, nextOffset)))) status = NOSHI_E_MALFORMED;
            if (status != NOSHI_OK) {
                NSLog(@"noshigram: public forwards rejected: %s", noshi_status_name(status));
                failure = @"MALFORMED";
            } else {
                items = [NSMutableArray arrayWithCapacity:count];
                for (size_t i = 0; i < count; ++i) {
                    long long key = rows[i].peer_kind == 1 ? rows[i].peer_id : -rows[i].peer_id;
                    [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithLongLong:key], @"peer",
                                      [NSNumber numberWithInt:rows[i].item_id], @"item", [NSNumber numberWithInt:rows[i].date], @"date",
                                      [NSNumber numberWithInt:rows[i].views], @"views", [NSNumber numberWithBool:rows[i].story], @"story", nil]];
                }
                /* no session: this is not the session's thread, so a channel that came without its photo stays without one */
                people = NoshiPeopleOfAnswer(nil, result->value);
                if (nextOffset[0]) next = [NSString stringWithUTF8String:nextOffset];
            }
        }
        NSArray *deliveredItems = [[items copy] autorelease];
        NSDictionary *names = [[people copy] autorelease];
        NSString *following = [[next copy] autorelease];
        NSString *problem = [[failure copy] autorelease];
        [self deliverMain:^{ done(deliveredItems, names, following, total, problem); [done release]; }];
    }];
    [cursor release];
}

@end

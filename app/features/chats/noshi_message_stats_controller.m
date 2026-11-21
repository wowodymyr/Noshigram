#import "noshi_message_stats_controller.h"

#import "noshi_avatar_cache.h"
#import "noshi_avatar_view.h"
#import "noshi_chart_view.h"
#import "noshi_emoji_label.h"
#import "noshi_message.h"
#import "noshi_person.h"
#import "noshi_session_stats.h"
#import "noshi_theme.h"
#import "noshi_time.h"
#import "noshi_weak_reference.h"

/* the public forwards past this many are not listed, as the reactors of a post are not */
#define FORWARDS_MAX 300
/* a post with this few points in its graph is a young one: its daily graph is nearly empty, and the server offers the hourly one around its last day */
#define ZOOM_POINTS_MAX 5

@interface NoshiStatsForwardRowView : UIView {
    NoshiAvatarView *_avatar;
    NoshiEmojiLabel *_name;
    NoshiEmojiLabel *_line;
    NoshiPerson *_person;
    NoshiAvatarCache *_cache;
}
- (id)initWithPerson:(NoshiPerson *)person key:(long long)key name:(NSString *)name line:(NSString *)line cache:(NoshiAvatarCache *)cache;
@end

@implementation NoshiStatsForwardRowView

- (id)initWithPerson:(NoshiPerson *)person key:(long long)key name:(NSString *)name line:(NSString *)line cache:(NoshiAvatarCache *)cache {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _person = [person retain];
    _cache = [cache retain];
    _avatar = [[NoshiAvatarView alloc] init];
    _avatar.circular = YES;
    _avatar.seed = (NSUInteger)((key < 0 ? -key : key) % 1000003);
    _avatar.initials = person ? person.initials : NoshiInitialsOfName(name);
    [self addSubview:_avatar];
    _name = [[NoshiEmojiLabel alloc] init];
    _name.font = NoshiFontSemibold(16);
    _name.textColor = NoshiColorTitle();
    _name.dropsUndrawable = YES;
    _name.text = name;
    [self addSubview:_name];
    _line = [[NoshiEmojiLabel alloc] init];
    _line.font = NoshiFontRegular(14);
    _line.textColor = NoshiColorSecondary();
    _line.text = line;
    [self addSubview:_line];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", name, line];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [_avatar setPhoto:_person.photo cache:_cache];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _avatar.frame = CGRectMake(12, 10, 44, 44);
    _name.frame = CGRectMake(68, 8, MAX(0, self.bounds.size.width - 80), 24);
    _line.frame = CGRectMake(68, 32, MAX(0, self.bounds.size.width - 80), 22);
}

- (void)dealloc {
    [_avatar release];
    [_name release];
    [_line release];
    [_person release];
    [_cache release];
    [super dealloc];
}

@end

@interface NoshiMessageStatsController () {
    NoshiSession *_session;
    NoshiDialog *_dialog;
    NoshiAvatarCache *_avatars;
    int32_t _messageId;
    int32_t _messageViews;
    int32_t _messageForwards;
    int32_t _messageReactions;
    NoshiWeakReference *_weak;

    NoshiStatsGraph *_viewsGraph;
    NoshiStatsGraph *_reactionsGraph;
    int32_t _dc;
    BOOL _graphsLoading;
    BOOL _graphsStarted;
    NSString *_graphsError;
    /* the chart views live on between rebuilds, which a page of public forwards causes, so a series the person switched off stays off */
    NSMutableDictionary *_chartViews;

    NSMutableArray *_forwards;
    NSMutableDictionary *_people;
    NSMutableSet *_offsets;
    NSString *_next;
    NSString *_forwardsError;
    int32_t _forwardsTotal;
    BOOL _forwardsLoading;
    BOOL _forwardsStarted;
    BOOL _forwardsLimited;
}
@end

@implementation NoshiMessageStatsController

- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog message:(NoshiMessage *)message avatars:(NoshiAvatarCache *)avatars {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _dialog = [dialog retain];
    _avatars = [avatars retain];
    _messageId = message.messageId;
    _messageViews = message.views;
    _messageForwards = message.forwards;
    for (NoshiReaction *reaction in message.reactions) {
        if (reaction.row.kind != NOSHI_REACTION_PAID) _messageReactions += reaction.row.count;
    }
    _forwards = [[NSMutableArray alloc] init];
    _people = [[NSMutableDictionary alloc] init];
    _offsets = [[NSMutableSet alloc] init];
    _chartViews = [[NSMutableDictionary alloc] init];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"stats.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_dialog release];
    [_avatars release];
    [_viewsGraph release];
    [_reactionsGraph release];
    [_graphsError release];
    [_forwards release];
    [_people release];
    [_offsets release];
    [_chartViews release];
    [_next release];
    [_forwardsError release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self loadGraphs];
}

- (void)themeDidChange { [self rebuild]; }

#pragma mark graphs

- (void)loadGraphs {
    if (_graphsLoading) return;
    _graphsLoading = YES;
    [_graphsError release];
    _graphsError = nil;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadStatsOfMessageId:_messageId ofDialog:_dialog completion:^(NoshiStatsGraph *views, NoshiStatsGraph *reactions, int32_t dc, NSString *errorName) {
        NoshiMessageStatsController *page = weak.target;
        if (!page) return;
        page->_graphsLoading = NO;
        page->_graphsStarted = YES;
        if (errorName) {
            page->_graphsError = [errorName copy];
        } else {
            page->_dc = dc;
            page->_viewsGraph = [views retain];
            page->_reactionsGraph = [reactions retain];
            [page completeGraphs];
            [page loadForwards];
        }
        [page rebuild];
    }];
}

/* a graph that came as a token is asked for, and a young post gets the hourly graph in place of an almost empty daily one */
- (void)completeGraphs {
    NoshiWeakReference *weak = _weak;
    NoshiStatsGraph *views = _viewsGraph, *reactions = _reactionsGraph;
    if (views.kind == NOSHI_GRAPH_ASYNC) {
        [_session loadGraphWithToken:views.token x:0 hasX:NO dc:_dc completion:^(NoshiStatsGraph *graph, NSString *errorName) {
            NoshiMessageStatsController *page = weak.target;
            if (!page || page->_viewsGraph != views) return;
            if (graph) {
                [page->_viewsGraph release];
                page->_viewsGraph = [graph retain];
                [page zoomViewsGraph];
            } else {
                NSLog(@"noshigram: the views graph did not load: %@", errorName);
            }
            [page rebuild];
        }];
    } else {
        [self zoomViewsGraph];
    }
    if (reactions.kind == NOSHI_GRAPH_ASYNC) {
        [_session loadGraphWithToken:reactions.token x:0 hasX:NO dc:_dc completion:^(NoshiStatsGraph *graph, NSString *errorName) {
            NoshiMessageStatsController *page = weak.target;
            if (!page || page->_reactionsGraph != reactions) return;
            if (graph) {
                [page->_reactionsGraph release];
                page->_reactionsGraph = [graph retain];
            } else {
                NSLog(@"noshigram: the reactions graph did not load: %@", errorName);
            }
            [page rebuild];
        }];
    }
}

- (void)zoomViewsGraph {
    NoshiStatsGraph *views = _viewsGraph;
    const noshi_chart *chart = views.chartData.chart;
    if (views.kind != NOSHI_GRAPH_JSON || !chart || chart->points > ZOOM_POINTS_MAX || !views.zoomToken.length) return;
    NoshiWeakReference *weak = _weak;
    [_session loadGraphWithToken:views.zoomToken x:chart->x[chart->points - 1] hasX:YES dc:_dc completion:^(NoshiStatsGraph *graph, NSString *errorName) {
        NoshiMessageStatsController *page = weak.target;
        if (!page || page->_viewsGraph != views) return;
        /* the daily graph stays when the hourly one is not there, which is the case for a post of the last hours */
        if (graph && graph.kind == NOSHI_GRAPH_JSON) {
            [page->_viewsGraph release];
            page->_viewsGraph = [graph retain];
            [page rebuild];
        } else if (errorName) {
            NSLog(@"noshigram: the hourly views graph did not load: %@", errorName);
        }
    }];
}

#pragma mark public forwards

- (void)loadForwards {
    if (_forwardsLoading || (_forwardsStarted && !_next && !_forwardsError) || _forwards.count >= FORWARDS_MAX) return;
    NSString *cursor = [[_next copy] autorelease];
    _forwardsLoading = YES;
    [_forwardsError release];
    _forwardsError = nil;
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadPublicForwardsOfMessageId:_messageId ofDialog:_dialog dc:_dc offset:cursor completion:^(NSArray *items, NSDictionary *people, NSString *next, int32_t total, NSString *errorName) {
        NoshiMessageStatsController *page = weak.target;
        if (!page) return;
        page->_forwardsLoading = NO;
        page->_forwardsStarted = YES;
        if (errorName) {
            page->_forwardsError = [[NSString stringWithFormat:NSLocalizedString(@"stats.error", nil), errorName] copy];
        } else if (next && ([page->_offsets containsObject:next] || (cursor && [next isEqualToString:cursor]))) {
            page->_forwardsError = [NSLocalizedString(@"stats.badpage", nil) copy];
        } else {
            if (cursor) [page->_offsets addObject:cursor];
            [page->_people addEntriesFromDictionary:people];
            NSUInteger room = FORWARDS_MAX - page->_forwards.count;
            NSUInteger take = MIN(room, items.count);
            if (take) [page->_forwards addObjectsFromArray:[items subarrayWithRange:NSMakeRange(0, take)]];
            page->_forwardsTotal = total;
            page->_forwardsLimited = take < items.count || (next && page->_forwards.count >= FORWARDS_MAX);
            [page->_next release];
            page->_next = [next copy];
        }
        [page rebuild];
    }];
}

#pragma mark rows

static NSString *NoshiStatsCount(int64_t value) {
    return [NSString stringWithFormat:@"%lld", (long long)value];
}

- (NoshiSettingsRow *)chartRowForGraph:(NoshiStatsGraph *)graph title:(NSString *)title {
    NoshiChartView *chart = [_chartViews objectForKey:title];
    if (!chart || chart.data != graph.chartData) {
        chart = [[[NoshiChartView alloc] initWithFrame:CGRectZero] autorelease];
        chart.title = title;
        chart.data = graph.chartData;
        [_chartViews setObject:chart forKey:title];
    }
    return [NoshiSettingsRow viewRowWithView:chart height:^CGFloat(CGFloat width) { return [chart heightForWidth:width]; }];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    NSMutableArray *overview = [NSMutableArray array];
    [overview addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.views", nil) value:NoshiStatsCount(_messageViews) tap:nil]];
    if (_messageReactions > 0) [overview addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.reactions", nil) value:NoshiStatsCount(_messageReactions) tap:nil]];
    if (_messageForwards > 0) {
        [overview addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.shares", nil) value:NoshiStatsCount(_messageForwards) tap:nil]];
        if (_forwardsStarted && !_forwardsError) {
            int32_t publicShares = MIN(_forwardsTotal, _messageForwards);
            [overview addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.shares.public", nil) value:NoshiStatsCount(publicShares) tap:nil]];
            [overview addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.shares.private", nil) value:NoshiStatsCount(_messageForwards - publicShares) tap:nil]];
        }
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:overview]];

    NSMutableArray *charts = [NSMutableArray array];
    if (_graphsLoading) {
        [charts addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.loading", nil) value:nil tap:nil]];
    } else if (_graphsError) {
        NSString *text;
        if ([_graphsError isEqualToString:@"CHAT_ADMIN_REQUIRED"]) text = NSLocalizedString(@"stats.denied", nil);
        else if ([_graphsError hasPrefix:@"FLOOD_WAIT_"] || [_graphsError hasPrefix:@"FLOOD_PREMIUM_WAIT_"])
            text = [NSString stringWithFormat:NSLocalizedString(@"stats.wait", nil), [[_graphsError substringFromIndex:[_graphsError rangeOfString:@"_" options:NSBackwardsSearch].location + 1] intValue]];
        else text = [NSString stringWithFormat:NSLocalizedString(@"stats.error", nil), _graphsError];
        [charts addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.retry", nil) subtitle:text value:nil tap:^{
            [(NoshiMessageStatsController *)weak.target loadGraphs];
        }]];
    } else {
        struct { NoshiStatsGraph *graph; NSString *title; } entries[2] = {
            {_viewsGraph, NSLocalizedString(@"stats.chart.views", nil)},
            {_reactionsGraph, NSLocalizedString(@"stats.chart.reactions", nil)}
        };
        for (int i = 0; i < 2; ++i) {
            NoshiStatsGraph *graph = entries[i].graph;
            if (graph.kind == NOSHI_GRAPH_JSON) {
                [charts addObject:[self chartRowForGraph:graph title:entries[i].title]];
            } else if (graph.kind == NOSHI_GRAPH_ASYNC) {
                [charts addObject:[NoshiSettingsRow rowWithTitle:entries[i].title subtitle:NSLocalizedString(@"stats.loading", nil) value:nil tap:nil]];
            } else if (graph.kind == NOSHI_GRAPH_ERROR) {
                /* the server says why, usually that the post is too young or too few people reacted */
                [charts addObject:[NoshiSettingsRow rowWithTitle:entries[i].title subtitle:graph.errorText value:nil tap:nil]];
            }
        }
    }
    if (charts.count) [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:charts]];

    if (_forwardsStarted || _forwardsLoading || _forwardsError) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *entry in _forwards) {
            NSNumber *key = [entry objectForKey:@"peer"];
            NoshiPerson *person = [_people objectForKey:key];
            NSString *name = person.name.length ? person.name : [NSString stringWithFormat:@"ID %@", key];
            int32_t views = [[entry objectForKey:@"views"] intValue];
            int32_t date = [[entry objectForKey:@"date"] intValue];
            BOOL story = [[entry objectForKey:@"story"] boolValue];
            NSMutableArray *parts = [NSMutableArray array];
            if (story) [parts addObject:NSLocalizedString(@"stats.forwards.story", nil)];
            if (views > 0) [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"stats.forwards.views", nil), (int)views]];
            if (date > 0) [parts addObject:NoshiMediaTimeText(date)];
            NoshiStatsForwardRowView *view = [[[NoshiStatsForwardRowView alloc] initWithPerson:person key:key.longLongValue name:name
                                                                                              line:[parts componentsJoinedByString:@" · "] cache:_avatars] autorelease];
            [rows addObject:[NoshiSettingsRow viewRowWithView:view height:^CGFloat(CGFloat width) { (void)width; return 64; }]];
        }
        if (_forwardsLoading) {
            [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.loading", nil) value:nil tap:nil]];
        } else if (_forwardsError) {
            [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.retry", nil) subtitle:_forwardsError value:nil tap:^{
                [(NoshiMessageStatsController *)weak.target loadForwards];
            }]];
        } else if (_next && _forwards.count < FORWARDS_MAX) {
            [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"group.tab.more", nil) value:nil tap:^{
                [(NoshiMessageStatsController *)weak.target loadForwards];
            }]];
        } else if (!_forwards.count) {
            [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"stats.forwards.empty", nil) value:nil tap:nil]];
        }
        NSString *footer = _forwardsLimited ? NSLocalizedString(@"stats.forwards.limit", nil) : nil;
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"stats.forwards.header", nil) footer:footer rows:rows]];
    }
    self.sections = sections;
    [self reloadSettings];
}

@end

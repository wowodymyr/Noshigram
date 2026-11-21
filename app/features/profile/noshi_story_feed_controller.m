#import "noshi_story_feed_controller.h"

#import "noshi_gift_grid_view.h"
#import "noshi_story_viewer_controller.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

@interface NoshiStoryFeedController () <NoshiGiftGridDelegate> {
    NoshiProfileFeed *_feed;
    NoshiDialog *_owner;
    NoshiGiftGridView *_grid;
    UILabel *_status;
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiStoryFeedController

- (id)initWithSession:(NoshiSession *)session kind:(NoshiProfileFeedKind)kind owner:(NoshiDialog *)owner avatars:(NoshiAvatarCache *)avatars
                media:(NoshiMediaCache *)media {
    self = [super initWithSession:session avatars:avatars media:media];
    if (!self) return nil;
    _owner = [owner retain];
    _feed = [[NoshiProfileFeed alloc] initWithSession:session kind:kind owner:owner];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.screenTitle = NSLocalizedString(kind == NoshiFeedPinnedStories ? @"profile.tab.stories" : @"profile.tab.archive", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    _grid.delegate = nil;
    [_feed release];
    [_owner release];
    [_grid release];
    [_status release];
    [super dealloc];
}

- (void)buildBodyInView:(UIView *)root {
    _grid = [[NoshiGiftGridView alloc] initWithMedia:self.media];
    _grid.delegate = self;
    [root addSubview:_grid];
    _status = [[UILabel alloc] init];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = NoshiColorSecondary();
    _status.textAlignment = NoshiTextAlignmentCenter;
    _status.numberOfLines = 0;
    [root addSubview:_status];
}

- (void)layoutBody:(CGRect)body {
    _grid.frame = body;
    _status.frame = CGRectMake(body.origin.x + 24, CGRectGetMidY(body) - 40, body.size.width - 48, 80);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self showState];
    [self reload];
}

- (void)reload {
    NoshiWeakReference *me = _weak;
    [_feed reload:^{ [(NoshiStoryFeedController *)me.target changed]; }];
}

- (void)changed {
    [_grid setTiles:_feed.tiles];
    [self showState];
}

- (void)showState {
    NSString *text = @"";
    if (!_feed.loaded) text = _feed.errorName ? [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), _feed.errorName] : NSLocalizedString(@"profile.loading", nil);
    else if (!_feed.items.count) text = NSLocalizedString(_feed.kind == NoshiFeedPinnedStories ? @"profile.stories.empty" : @"profile.archive.empty", nil);
    _status.text = text;
}

- (void)giftGridReachedEnd:(NoshiGiftGridView *)grid {
    (void)grid;
    NoshiWeakReference *me = _weak;
    [_feed loadMore:^{ [(NoshiStoryFeedController *)me.target changed]; }];
}

- (void)giftGrid:(NoshiGiftGridView *)grid didSelectIndex:(NSUInteger)index {
    (void)grid;
    if (index >= _feed.items.count) return;
    /* a second tap while a viewer is up or rising would stack another viewer on the first, and both would play the same story's sound */
    if (self.presentedViewController) return;
    NoshiStoryViewerController *viewer = [[[NoshiStoryViewerController alloc] initWithSession:self.session owner:_owner stories:_feed.items index:index
                                                                                          avatars:self.avatars media:self.media] autorelease];
    [self presentViewController:viewer animated:YES completion:nil];
}

@end

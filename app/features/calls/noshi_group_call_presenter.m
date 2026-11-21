#import "noshi_group_call_presenter.h"
#import "noshi_alert_view.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_avatar_cache.h"
#import "noshi_group_call_controller.h"
#import "noshi_group_call_state.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

@interface NoshiGroupCallPresenter () {
    UIViewController *(^_topController)(void);
    UIView *(^_host)(void);
    NoshiSession *_session;
    NoshiGroupCallController *_screen;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiGroupCall *_snapshot, *_pending;
    UIButton *_bar;
    NSTimer *_barTimer;
    BOOL _minimized, _minimizing;
}
@end

@implementation NoshiGroupCallPresenter

@synthesize session = _session;

- (id)initWithTopController:(UIViewController *(^)(void))topController host:(UIView *(^)(void))host {
    self = [super init];
    if (!self) return nil;
    _topController = [topController copy];
    _host = [host copy];
    return self;
}

- (void)dealloc {
    [_barTimer invalidate];
    [_barTimer release];
    [_bar removeFromSuperview];
    [_bar release];
    [_topController release];
    [_host release];
    [_screen release];
    [_avatars release];
    [_media release];
    [_snapshot release];
    [_pending release];
    [super dealloc];
}

- (BOOL)callIsShown { return _screen != nil; }

- (void)session:(NoshiSession *)session groupCallDidChange:(NoshiGroupCall *)call {
    if (_screen && _screen.finishing && call.callId != _screen.callId && call.phase != NoshiGroupPhaseEnded) {
        /* the next call waits until the screen of the one that ended is gone */
        [_pending release];
        _pending = [call retain];
        return;
    }
    if (call != _snapshot) {
        [_snapshot release];
        _snapshot = [call retain];
    }
    if (!_screen) {
        if (call.phase == NoshiGroupPhaseEnded) {
            /* a call that failed before its screen was shown is only worded */
            [self noticeForCall:call];
            return;
        }
        if (!_avatars) {
            NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
            NSString *directory = [[caches stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"avatars"];
            _avatars = [[NoshiAvatarCache alloc] initWithSession:session directory:directory];
            _media = [[NoshiMediaCache alloc] initWithSession:session directory:[[caches stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"media"]];
        }
        _screen = [[NoshiGroupCallController alloc] initWithSession:session];
        _screen.avatars = _avatars;
        _screen.media = _media;
        /* not retained by the block: the screen holds the block */
        __block NoshiGroupCallController *shown = _screen;
        _screen.onMinimize = ^{ [self minimize]; };
        _screen.onFinish = ^{
            if (_screen != shown) return;
            [self hideBar];
            _minimizing = NO;
            NoshiGroupCall *last = [[_snapshot retain] autorelease];
            [_snapshot release];
            _snapshot = nil;
            [_screen release];
            _screen = nil;
            [self noticeForCall:last];
            NoshiGroupCall *next = [[_pending retain] autorelease];
            [_pending release];
            _pending = nil;
            if (next) [self session:session groupCallDidChange:next];
        };
        UIViewController *top = _topController();
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:_screen animated:YES completion:nil];
    }
    if (_minimized) {
        if (call.phase == NoshiGroupPhaseEnded) {
            /* the screen of a call that ended while it was folded is put back for the moment it shows its end, so it closes the way every screen does */
            [self hideBar];
            [self presentFoldedScreen];
        } else {
            [self refreshBar];
        }
    }
    [_screen updateWithCall:call];
}

- (void)presentFoldedScreen {
    if (!_screen) return;
    UIViewController *top = _topController();
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:_screen animated:NO completion:nil];
}

#pragma mark the end

- (NSString *)noticeTextForCall:(NoshiGroupCall *)call {
    switch (call.end) {
    case NoshiGroupEndFinished: return NSLocalizedString(@"group.notice.finished", nil);
    case NoshiGroupEndNoCall: return NSLocalizedString(@"group.notice.nocall", nil);
    case NoshiGroupEndUnsupported: return NSLocalizedString(@"group.notice.unsupported", nil);
    case NoshiGroupEndRemoved: return NSLocalizedString(@"group.notice.removed", nil);
    case NoshiGroupEndFailed:
        return call.error.length ? [NSString stringWithFormat:NSLocalizedString(@"group.notice.failed.detail", nil), call.error] : NSLocalizedString(@"group.notice.failed", nil);
    default: return nil;
    }
}

- (void)noticeForCall:(NoshiGroupCall *)call {
    NSString *text = call.phase == NoshiGroupPhaseEnded ? [self noticeTextForCall:call] : nil;
    if (!text) return;
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:nil message:text delegate:nil cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

#pragma mark folded call

- (void)minimize {
    if (!_screen || _minimized || _screen.finishing) return;
    _minimized = YES;
    _minimizing = YES;
    NoshiGroupCallController *screen = _screen;
    /* the bar is there from the start, so a dismissal whose completion never comes does not leave the call with no way back */
    [self showBar];
    [screen dismissViewControllerAnimated:YES completion:^{
        if (_screen != screen) return;
        _minimizing = NO;
        if (_minimized) [self showBar];
    }];
}

- (void)restore {
    if (!_screen || !_minimized || (_minimizing && _screen.presentingViewController)) return;
    _minimizing = NO;
    _minimized = NO;
    [self hideBar];
    UIViewController *top = _topController();
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:_screen animated:YES completion:nil];
}

- (void)showBar {
    if (!_bar) {
        _bar = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _bar.backgroundColor = [UIColor colorWithRed:0.18f green:0.72f blue:0.35f alpha:1];
        _bar.layer.cornerRadius = 16;
        _bar.titleLabel.font = NoshiFontSemibold(13);
        _bar.titleLabel.lineBreakMode = UILineBreakModeTailTruncation;
        _bar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [_bar addTarget:self action:@selector(restore) forControlEvents:UIControlEventTouchUpInside];
    }
    [self refreshBar];
    if (!_barTimer) _barTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(refreshBar) userInfo:nil repeats:YES] retain];
    UIView *host = _host();
    CGFloat width = MIN(MAX(0, host.bounds.size.width - 104), 260);
    _bar.frame = CGRectMake(floor((host.bounds.size.width - width) / 2), NoshiStatusBarHeight() + 4, width, 32);
    [host addSubview:_bar];
}

- (void)refreshBar {
    NSString *name = _snapshot.title.length ? _snapshot.title : (_snapshot.chatTitle.length ? _snapshot.chatTitle : NSLocalizedString(@"group.title", nil));
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"group.return", nil), name];
    if (_snapshot.phase == NoshiGroupPhaseActive && _snapshot.startedAt > 0) {
        NSInteger seconds = MAX(0, (NSInteger)([NSDate timeIntervalSinceReferenceDate] - _snapshot.startedAt));
        title = [NSString stringWithFormat:@"%@ · %ld:%02ld", name, (long)(seconds / 60), (long)(seconds % 60)];
    } else if (_snapshot.phase == NoshiGroupPhaseReconnecting) {
        title = NSLocalizedString(@"call.reconnecting", nil);
    }
    [_bar setTitle:title forState:UIControlStateNormal];
    /* a screen that was pushed or put back under the bar must not cover the way back into the call */
    UIView *host = _host();
    if (_bar.superview && _bar.superview == host) [host bringSubviewToFront:_bar];
    else if (_bar && _barTimer) [host addSubview:_bar];
}

- (void)hideBar {
    _minimized = NO;
    [_barTimer invalidate];
    [_barTimer release];
    _barTimer = nil;
    [_bar removeFromSuperview];
}

@end

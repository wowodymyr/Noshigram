#import "noshi_round_playback.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_audio_session.h"
#import "noshi_chat_settings.h"
#import "noshi_music_player.h"
#import "noshi_platform.h"
#import "noshi_symbol.h"

NSString *const NoshiRoundPlaybackDidChangeNotification = @"NoshiRoundPlaybackDidChange";

#define PIP_SIDE 128.0
#define PIP_MARGIN 8.0
#define PIP_TOP_CLEARANCE 28.0
#define PIP_CLOSE_SIDE 30.0

@implementation NoshiRoundVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

/* the circle that floats over the app while the row of the message that plays is not on screen: the picture, the ring of the
   progress, a cross that ends it, and a triangle while it is paused. it is dragged and settles at the nearer side */
@interface NoshiRoundPipView : UIView <UIGestureRecognizerDelegate> {
    NoshiRoundVideoView *_video;
    CAShapeLayer *_ring;
    UIImageView *_paused;
    UIButton *_close;
    NSTimer *_timer;
    CGPoint _grab;
    BOOL _right;
    CGFloat _heightFraction;
}
- (void)attachTo:(UIView *)parent;
- (void)detach;
- (void)refresh;
- (void)settleAnimated:(BOOL)animated;
@end

@interface NoshiRoundPipHost : UIView
@end

@implementation NoshiRoundPipHost
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    for (UIView *view in self.subviews) {
        if ([view isKindOfClass:[NoshiRoundPipView class]]) [(NoshiRoundPipView *)view settleAnimated:NO];
    }
}
@end

@interface NoshiRoundPlayback () {
    AVPlayer *_player;
    AVPlayerItem *_item;
    NSString *_key;
    id<NoshiRoundChain> _chain;
    id _host;
    NSTimer *_watch;
    NoshiRoundPipView *_pip;
}
- (void)refreshPip;
@end

@implementation NoshiRoundPipView

- (id)init {
    self = [super initWithFrame:CGRectMake(0, 0, PIP_SIDE, PIP_SIDE)];
    if (!self) return nil;
    _right = YES;
    _heightFraction = 0.72;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.4f;
    self.layer.shadowRadius = 6;
    self.layer.shadowOffset = CGSizeMake(0, 2);
    _video = [[NoshiRoundVideoView alloc] initWithFrame:self.bounds];
    _video.userInteractionEnabled = NO;
    _video.backgroundColor = [UIColor blackColor];
    _video.layer.cornerRadius = PIP_SIDE / 2;
    _video.layer.masksToBounds = YES;
    ((AVPlayerLayer *)_video.layer).videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self addSubview:_video];
    _ring = [[CAShapeLayer layer] retain];
    _ring.frame = self.bounds;
    _ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 1.5, 1.5)].CGPath;
    _ring.fillColor = NULL;
    _ring.strokeColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    _ring.lineWidth = 3;
    _ring.lineCap = kCALineCapRound;
    _ring.strokeEnd = 0;
    /* the stroke starts at the top and runs clockwise, which a path from three o'clock does not */
    _ring.transform = CATransform3DMakeRotation((CGFloat)(-M_PI / 2), 0, 0, 1);
    [self.layer addSublayer:_ring];
    _paused = [[UIImageView alloc] initWithImage:NoshiSymbolImage(NoshiSymbolPlay, 40, [UIColor whiteColor])];
    _paused.center = CGPointMake(PIP_SIDE / 2, PIP_SIDE / 2);
    _paused.userInteractionEnabled = NO;
    [self addSubview:_paused];
    _close = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _close.frame = CGRectMake(PIP_SIDE - PIP_CLOSE_SIDE, 0, PIP_CLOSE_SIDE, PIP_CLOSE_SIDE);
    _close.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _close.layer.cornerRadius = PIP_CLOSE_SIDE / 2;
    [_close setImage:NoshiSymbolImage(NoshiSymbolClose, 14, [UIColor whiteColor]) forState:UIControlStateNormal];
    _close.accessibilityLabel = NSLocalizedString(@"music.stop", nil);
    [_close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_close];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)] autorelease];
    tap.delegate = self;
    [self addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)] autorelease];
    pan.delegate = self;
    [self addGestureRecognizer:pan];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged:)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    ((AVPlayerLayer *)_video.layer).player = nil;
    [_video release];
    [_ring release];
    [_paused release];
    [_close release];
    [super dealloc];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:[UIControl class]];
}

- (void)attachTo:(UIView *)parent {
    if (self.superview.superview != parent) {
        [self detach];
        NoshiRoundPipHost *host = [[[NoshiRoundPipHost alloc] initWithFrame:parent.bounds] autorelease];
        host.backgroundColor = [UIColor clearColor];
        host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [parent addSubview:host];
        [host addSubview:self];
        [self settleAnimated:NO];
    } else {
        [parent bringSubviewToFront:self.superview];
    }
    ((AVPlayerLayer *)_video.layer).player = [NoshiRoundPlayback sharedPlayback].player;
    if (!_timer) _timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self refresh];
}

- (void)detach {
    [_timer invalidate];
    _timer = nil;
    ((AVPlayerLayer *)_video.layer).player = nil;
    UIView *host = [[self.superview retain] autorelease];
    [self removeFromSuperview];
    [host removeFromSuperview];
}

- (void)refresh {
    _paused.hidden = [NoshiRoundPlayback sharedPlayback].playing;
    [self tick];
}

- (void)tick {
    _ring.strokeEnd = [[NoshiRoundPlayback sharedPlayback] progress];
}

- (void)tapped { [[NoshiRoundPlayback sharedPlayback] togglePause]; }
- (void)closeTapped { [[NoshiRoundPlayback sharedPlayback] stop]; }

/* the circle stands at the side it was let go at and at the height it had, as a share of the screen, so a turn of the phone keeps it
   where it was in the new frame */
- (void)settleAnimated:(BOOL)animated {
    UIView *parent = self.superview;
    if (!parent) return;
    CGRect bounds = parent.bounds;
    UIEdgeInsets safe = NoshiSafeInsets(parent.superview);
    CGFloat low = MAX(PIP_TOP_CLEARANCE, safe.top) + PIP_MARGIN + PIP_SIDE / 2;
    CGFloat high = MAX(low, bounds.size.height - safe.bottom - PIP_MARGIN - PIP_SIDE / 2);
    CGFloat y = MIN(high, MAX(low, low + (high - low) * _heightFraction));
    CGFloat x = _right ? bounds.size.width - safe.right - PIP_MARGIN - PIP_SIDE / 2 : safe.left + PIP_MARGIN + PIP_SIDE / 2;
    void (^move)(void) = ^{ self.center = CGPointMake(x, y); };
    if (!animated) {
        move();
        return;
    }
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:move completion:nil];
}

- (void)orientationChanged:(NSNotification *)note {
    (void)note;
    [self settleAnimated:NO];
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    UIView *parent = self.superview;
    if (!parent) return;
    if (pan.state == UIGestureRecognizerStateBegan) _grab = self.center;
    CGPoint shift = [pan translationInView:parent];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        self.center = CGPointMake(_grab.x + shift.x, _grab.y + shift.y);
        return;
    }
    if (pan.state != UIGestureRecognizerStateEnded && pan.state != UIGestureRecognizerStateCancelled) return;
    CGRect bounds = parent.bounds;
    UIEdgeInsets safe = NoshiSafeInsets(parent.superview);
    CGFloat low = MAX(PIP_TOP_CLEARANCE, safe.top) + PIP_MARGIN + PIP_SIDE / 2;
    CGFloat high = MAX(low, bounds.size.height - safe.bottom - PIP_MARGIN - PIP_SIDE / 2);
    _right = self.center.x >= bounds.size.width / 2;
    _heightFraction = high > low ? MIN(1, MAX(0, (self.center.y - low) / (high - low))) : 0;
    [self settleAnimated:YES];
}

@end

@implementation NoshiRoundPlayback

@synthesize host = _host;

+ (NoshiRoundPlayback *)sharedPlayback {
    static NoshiRoundPlayback *shared = nil;
    if (!shared) shared = [[NoshiRoundPlayback alloc] init];
    return shared;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(musicChanged:) name:NoshiMusicPlayerDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(appBackgrounded:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}

- (AVPlayer *)player { return _player; }
- (NSString *)key { return _key; }
- (BOOL)active { return _player != nil; }
- (BOOL)playing { return _player != nil && _player.rate > 0; }

- (BOOL)isActiveKey:(NSString *)key {
    return _player != nil && key != nil && [_key isEqualToString:key];
}

- (NSTimeInterval)duration {
    NSTimeInterval length = CMTimeGetSeconds(_item.duration);
    return length > 0 && length < 1e9 ? length : 0;
}

- (CGFloat)progress {
    NSTimeInterval length = [self duration], at = CMTimeGetSeconds(_player.currentTime);
    return length > 0 && at >= 0 ? (CGFloat)MIN(1, at / length) : 0;
}

- (void)changed {
    [self refreshPip];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiRoundPlaybackDidChangeNotification object:self];
}

- (BOOL)beginWithURL:(NSURL *)url key:(NSString *)key chain:(id<NoshiRoundChain>)chain {
    if (!url || !key.length || !NoshiAudioSessionBeginPlayback()) return NO;
    [self tearDown];
    [[NoshiMusicPlayer sharedPlayer] pauseForMedia];
    _item = [[AVPlayerItem playerItemWithURL:url] retain];
    _player = [[AVPlayer playerWithPlayerItem:_item] retain];
    _key = [key copy];
    _chain = chain;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    _watch = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(watchItem:) userInfo:nil repeats:YES];
    [_player play];
    [self applySpeed];
    [self changed];
    return YES;
}

/* the player, the item and what hangs on them go; the host and the chain are the owners' to let go */
- (void)tearDown {
    [_watch invalidate];
    _watch = nil;
    if (_item) [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_item];
    [_player pause];
    [_player release];
    _player = nil;
    [_item release];
    _item = nil;
    [_key release];
    _key = nil;
    _chain = nil;
}

- (void)stop {
    if (!_player) return;
    [self tearDown];
    [self changed];
}

/* a failed item never ends and never plays, so the circle would hang there with nothing in it */
- (void)watchItem:(NSTimer *)timer {
    (void)timer;
    if (_item.status != AVPlayerItemStatusFailed) return;
    NSLog(@"noshigram: round video does not play: %@", _item.error);
    [self stop];
}

- (void)itemEnded:(NSNotification *)note {
    (void)note;
    NSString *ended = [[_key copy] autorelease];
    id<NoshiRoundChain> chain = _chain;
    [self stop];
    if (chain && ended) [chain roundPlayback:self didFinishKey:ended];
}

- (void)applySpeed {
    if ([self playing]) _player.rate = [NoshiMusicPlayer sharedPlayer].speed;
}

- (void)togglePause {
    if (!_player) return;
    if ([self playing]) {
        [_player pause];
    } else {
        if (!NoshiAudioSessionBeginPlayback()) return;
        [[NoshiMusicPlayer sharedPlayer] pauseForMedia];
        [_player play];
        [self applySpeed];
    }
    [self changed];
}

- (void)seekToFraction:(CGFloat)fraction {
    NSTimeInterval length = [self duration];
    if (length <= 0) return;
    [_player seekToTime:CMTimeMakeWithSeconds(length * MIN(1, MAX(0, fraction)), 600)];
}

- (void)step:(NSInteger)direction {
    if (!_player || !_chain || !_key) return;
    NSString *from = [[_key copy] autorelease];
    [_chain roundPlayback:self stepFromKey:from direction:direction];
}

- (void)forgetChain:(id)chain {
    if ((id)_chain == chain) _chain = nil;
}

- (void)setHost:(id)host {
    _host = host;
    [self refreshPip];
}

- (void)releaseHost:(id)host {
    if (_host != host) return;
    _host = nil;
    [self refreshPip];
}

/* a song that starts takes the audio output, and the circle that played gives it up */
- (void)musicChanged:(NSNotification *)note {
    (void)note;
    NoshiMusicState state = [NoshiMusicPlayer sharedPlayer].state;
    if (_player && (state == NoshiMusicStatePlaying || state == NoshiMusicStateLoading)) {
        [self stop];
        return;
    }
    [self applySpeed];
}

/* a circle that plays pauses when the app goes away, if the person asked for that; the sound of a circle is not a background audio */
- (void)appBackgrounded:(NSNotification *)note {
    (void)note;
    if ([self playing] && NoshiChatFlagGet(NoshiChatFlagPauseRoundOnMinimize)) [self togglePause];
}

/* the circle floats while a video message plays and no row shows it. it hangs on the view of the root controller, which turns with
   the interface, where the window of an old system stays upright */
- (void)refreshPip {
    BOOL floating = _player != nil && _host == nil;
    if (!floating) {
        [_pip detach];
        [_pip release];
        _pip = nil;
        return;
    }
    id delegate = [UIApplication sharedApplication].delegate;
    UIWindow *window = [delegate respondsToSelector:@selector(window)] ? [delegate window] : nil;
    UIView *parent = window.rootViewController.view;
    if (!parent) return;
    if (!_pip) _pip = [[NoshiRoundPipView alloc] init];
    [_pip attachTo:parent];
}

@end

#import "noshi_mini_player.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_classic_chrome.h"
#import "noshi_emoji_label.h"
#import "noshi_music_player.h"
#import "noshi_music_sheet.h"
#import "noshi_platform.h"
#import "noshi_round_playback.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"

#define STRIP_HEIGHT 46.0
#define BUTTON_WIDTH 40.0
#define WAVE_LENGTH 14.0
#define WAVE_PERIOD 1.2

@interface NoshiMiniPlayer () {
    NoshiEmojiLabel *_title;
    UIButton *_previous;
    UIButton *_toggle;
    UIButton *_next;
    UIButton *_close;
    UIView *_line;
    UIImageView *_backdrop;
    UIView *_card;
    UIView *_lead;
    UIImageView *_leadGlyph;
    UIImageView *_leadCover;
    NoshiEmojiLabel *_subtitle;
    UIView *_track;
    UIView *_indicator;
    CALayer *_waveClip;
    CAShapeLayer *_wave;
    CALayer *_rest;
    CGFloat _waveWidth;
    BOOL _waving;
    UIColor *_tone;
    NSTimer *_timer;
    CGFloat _fraction;
    BOOL _showing;
    BOOL _pill;
    UIColor *_surface;
    void (^_changeHandler)(void);
    void (^_openHandler)(void);
    void (^_closeHandler)(void);
}
@end

@implementation NoshiMiniPlayer

@synthesize showing = _showing;
@synthesize pill = _pill;
@synthesize changeHandler = _changeHandler;
@synthesize openHandler = _openHandler;
@synthesize closeHandler = _closeHandler;

+ (BOOL)isActive {
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    /* a video message that plays holds the output, so the strip is its and not the one of the song it paused */
    return [NoshiRoundPlayback sharedPlayback].active || (player.state != NoshiMusicStateIdle && player.track != nil);
}

+ (CGFloat)height { return STRIP_HEIGHT; }
+ (CGFloat)heightForPill:(BOOL)pill { return [self height]; }

/* the primary of a scheme made from a color of the cover: pale and soft on the dark theme, deep on the light one, whatever the cover's own brightness was */
static UIColor *NoshiStripTonalPrimary(UIColor *tone) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0, hue = 0, saturation = 0, value = 0;
    if (![tone getRed:&red green:&green blue:&blue alpha:&alpha]) return NoshiColorAccent();
    NoshiRGBToHSV(red, green, blue, &hue, &saturation, &value);
    if (NoshiThemeIsDark()) NoshiHSVToRGB(hue, MIN(saturation, 0.5), 0.88, &red, &green, &blue);
    else NoshiHSVToRGB(hue, MIN(0.85, MAX(saturation, 0.2)), 0.45, &red, &green, &blue);
    return [UIColor colorWithRed:red green:green blue:blue alpha:1];
}

static UIButton *NoshiStripButton(NoshiSymbol symbol, id target, SEL action, NSString *label) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:NoshiSymbolImage(symbol, 20, NoshiClassicStripInk()) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    button.accessibilityLabel = NSLocalizedString(label, nil);
    return button;
}

- (void)setPill:(BOOL)pill {
    if (pill == _pill) return;
    _pill = pill;
    [self setNeedsLayout];
}

- (UIColor *)key { return _tone ? NoshiStripTonalPrimary(_tone) : NoshiColorAccent(); }

/* the card in the colors of its key: the surface, the tile, the keys, the bar. a tone makes the card a scheme of that color and its progress a wave, no tone is the accent of the app */
- (void)applyScheme {
}

- (void)setTone:(UIColor *)tone surface:(UIColor *)surface animated:(BOOL)animated {
    BOOL layoutChanges = (tone != nil) != (_tone != nil);
    [_tone release];
    _tone = [tone retain];
    [_surface release];
    _surface = [surface retain];
    if (animated && _card && self.window && !NoshiReduceMotionEnabled()) {
        [UIView transitionWithView:_card duration:0.6 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ [self applyScheme]; } completion:nil];
    } else {
        [self applyScheme];
    }
    if (layoutChanges) [self setNeedsLayout];
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.clipsToBounds = YES;
    /* a plain black or white ground, as the pinned message has, and not the purple of the bars: the chat showed through the strip and the plate made a stripe */
    self.backgroundColor = NoshiClassicStripGround();
    _title = [[NoshiEmojiLabel alloc] init];
    _title.font = [UIFont boldSystemFontOfSize:14];
    _title.textColor = NoshiClassicStripInk();
    _title.dropsUndrawable = YES;
    [self addSubview:_title];
    _title.userInteractionEnabled = YES;
    [_title addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPlayer)] autorelease]];
    _previous = [NoshiStripButton(NoshiSymbolPrevious, self, @selector(previousTapped), @"music.previous") retain];
    _toggle = [NoshiStripButton(NoshiSymbolPlay, self, @selector(toggleTapped), @"music.play") retain];
    _next = [NoshiStripButton(NoshiSymbolNext, self, @selector(nextTapped), @"music.next") retain];
    _close = [NoshiStripButton(NoshiSymbolClose, self, @selector(closeTapped), @"music.stop") retain];
    for (UIView *view in [NSArray arrayWithObjects:_previous, _toggle, _next, _close, nil]) [self addSubview:view];
    _line = [[UIView alloc] init];
    _line.backgroundColor = NoshiClassicStripEdge();
    /* the card floats between its gutters, so it has no line under it */
    _line.hidden = NO;
    [self addSubview:_line];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:NoshiMusicPlayerDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerChanged:) name:NoshiRoundPlaybackDidChangeNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
    [_tone release];
    [_surface release];
    [_waveClip release];
    [_wave release];
    [_rest release];
    [_card release];
    [_lead release];
    [_leadGlyph release];
    [_leadCover release];
    [_subtitle release];
    [_track release];
    [_indicator release];
    [_title release];
    [_previous release];
    [_toggle release];
    [_next release];
    [_close release];
    [_line release];
    [_backdrop release];
    [_changeHandler release];
    [_openHandler release];
    [_closeHandler release];
    [super dealloc];
}

- (void)playerChanged:(NSNotification *)note {
    (void)note;
    [self refresh];
}

- (void)refresh {
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    NoshiRoundPlayback *round = [NoshiRoundPlayback sharedPlayback];
    BOOL showing = [NoshiMiniPlayer isActive];
    if (showing) {
        BOOL playing = round.active ? round.playing : (player.state == NoshiMusicStatePlaying || player.state == NoshiMusicStateLoading);
        _title.text = round.active ? NSLocalizedString(@"round.title", nil) : NoshiTrackLine(player.track);
        [_toggle setImage:NoshiSymbolImage(playing ? NoshiSymbolPause : NoshiSymbolPlay, 22, NoshiClassicStripInk()) forState:UIControlStateNormal];
        _toggle.accessibilityLabel = NSLocalizedString(playing ? @"music.pause" : @"music.play", nil);
    }
    if (showing != _showing) {
        _showing = showing;
        /* the owner lays the strip in and out at its new height inside the animation, so the list under it slides instead of jumping when a voice
           message opens or ends the player; the strip stays visible until the collapse is done, and its clipping hides the rest */
        if (showing) self.hidden = NO;
        BOOL animate = self.window != nil && !NoshiReduceMotionEnabled();
        void (^change)(void) = ^{ if (_changeHandler) _changeHandler(); };
        if (!animate) {
            change();
            self.hidden = !_showing;
        } else {
            [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:change completion:^(BOOL finished) {
                (void)finished;
                self.hidden = !_showing;
            }];
        }
    }
    [self updateTimer];
    [self setNeedsLayout];
}

/* the line under the title and the thin bar along the foot of the card follow the sound; a song names its performer, and a voice or video message tells how far it is */
- (void)updateProgress {
}

/* the wave runs while the sound does and stands still when it is paused or when reduced motion is on */
- (void)updateWave {
    BOOL run = _tone && _waving && self.window && !NoshiReduceMotionEnabled();
    BOOL running = [_wave animationForKey:@"wave"] != nil;
    if (run && !running) {
        CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
        slide.fromValue = [NSNumber numberWithFloat:0];
        slide.toValue = [NSNumber numberWithFloat:(float)-WAVE_LENGTH];
        slide.duration = WAVE_PERIOD;
        slide.repeatCount = HUGE_VALF;
        [_wave addAnimation:slide forKey:@"wave"];
    } else if (!run && running) {
        [_wave removeAnimationForKey:@"wave"];
    }
}

/* the timer lives only while the card is on a screen and has a sound to follow, since it holds the card; a card taken off the screen lets it go */
- (void)updateTimer {
    BOOL want = NO;
    if (want && !_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    } else if (!want && _timer) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    [self updateProgress];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateTimer];
    if (self.window) [self refresh];
}

- (void)previousTapped {
    if ([NoshiRoundPlayback sharedPlayback].active) [[NoshiRoundPlayback sharedPlayback] step:-1];
    else [[NoshiMusicPlayer sharedPlayer] previous];
}
- (void)toggleTapped {
    if ([NoshiRoundPlayback sharedPlayback].active) [[NoshiRoundPlayback sharedPlayback] togglePause];
    else [[NoshiMusicPlayer sharedPlayer] togglePause];
}
- (void)nextTapped {
    if ([NoshiRoundPlayback sharedPlayback].active) [[NoshiRoundPlayback sharedPlayback] step:1];
    else [[NoshiMusicPlayer sharedPlayer] next];
}
- (void)closeTapped {
    if (_closeHandler) { _closeHandler(); return; }
    if ([NoshiRoundPlayback sharedPlayback].active) [[NoshiRoundPlayback sharedPlayback] stop];
    else [[NoshiMusicPlayer sharedPlayer] stop];
}
/* the sheet of the player has nothing for a video message, which has its own circle */
- (void)openPlayer {
    if (_openHandler) { _openHandler(); return; }
    if (![NoshiRoundPlayback sharedPlayback].active) [NoshiMusicSheet present];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    _backdrop.frame = self.bounds;
    _line.frame = CGRectMake(0, height - 1.0 / NoshiScreenScale(), width, 1.0 / NoshiScreenScale());
    CGFloat x = width - 4 - BUTTON_WIDTH;
    _close.frame = CGRectMake(x, 0, BUTTON_WIDTH, STRIP_HEIGHT);
    x -= BUTTON_WIDTH;
    _next.frame = CGRectMake(x, 0, BUTTON_WIDTH, STRIP_HEIGHT);
    x -= BUTTON_WIDTH;
    _toggle.frame = CGRectMake(x, 0, BUTTON_WIDTH, STRIP_HEIGHT);
    x -= BUTTON_WIDTH;
    _previous.frame = CGRectMake(x, 0, BUTTON_WIDTH, STRIP_HEIGHT);
    _title.frame = CGRectMake(16, (STRIP_HEIGHT - 20) / 2, MAX(0, x - 24), 20);
}

@end

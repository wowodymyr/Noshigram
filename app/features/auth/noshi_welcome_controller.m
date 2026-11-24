#import "noshi_welcome_controller.h"

#import "noshi_alert.h"
#import "noshi_proxy_settings.h"
#import "noshi_lottie_view.h"
#import "noshi_network_probe.h"
#import "noshi_page_dots_view.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_wave_background_view.h"
#import "noshi_flat_button.h"
#import "noshi_weak_reference.h"
#import "noshi_welcome_toast.h"
#import "noshi_welcome.h"
#include "noshi_bytes.h"

#define NOSHI_WELCOME_PAGES 6
/* the sticker of the network card: the duck with the phone and the cloud, from the welcome pages */
#define NETWORK_STICKER @"welcome_cloud"

/* what the card on screen says, which decides what its buttons do */
typedef enum {
    NoshiWelcomeToastNone = 0,
    /* Telegram does not answer: the card offers to ask again */
    NoshiWelcomeToastNoLink
} NoshiWelcomeToastKind;

/* page 0 is the animated icon, the others each carry one sticker */
static NSString *const NoshiWelcomeStickers[NOSHI_WELCOME_PAGES] = {
    nil, @"welcome_fast", @"welcome_free", @"welcome_secure", @"welcome_powerful", @"welcome_cloud"
};

@interface NoshiWelcomePage : UIView {
    UIView *_art;
    UILabel *_title;
    UILabel *_message;
}
@property (nonatomic, readonly) UIView *art;
@property (nonatomic, readonly) UILabel *title;
@property (nonatomic, readonly) UILabel *message;
- (id)initWithIndex:(NSInteger)index;
@end

@implementation NoshiWelcomePage

@synthesize art = _art;
@synthesize title = _title;
@synthesize message = _message;

static UILabel *NoshiWelcomeLabel(UIColor *color, NSInteger lines) {
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.textAlignment = NoshiTextAlignmentCenter;
    label.numberOfLines = lines;
    label.adjustsFontSizeToFitWidth = NO;
    return label;
}

- (id)initWithIndex:(NSInteger)index {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    NSString *sticker = NoshiWelcomeStickers[index];
    _art = [(sticker ? (UIView *)[[[NoshiLottieView alloc] initWithAnimationNamed:sticker] autorelease]
                     : (UIView *)[[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"splash_icon"]] autorelease]) retain];
    _title = [NoshiWelcomeLabel(NoshiColorTitle(), 1) retain];
    _message = [NoshiWelcomeLabel(NoshiColorMessage(), 0) retain];
    _title.text = NSLocalizedString(([NSString stringWithFormat:@"welcome.title.%d", (int)index]), nil);
    _message.text = NSLocalizedString(([NSString stringWithFormat:@"welcome.message.%d", (int)index]), nil);
    [self addSubview:_art];
    [self addSubview:_title];
    [self addSubview:_message];
    return self;
}

- (void)dealloc {
    [_art release];
    [_title release];
    [_message release];
    [super dealloc];
}

@end

@interface NoshiWelcomeController () {
    NoshiWaveBackgroundView *_backdrop;
    UIScrollView *_scroll;
    NSMutableArray *_pages;
    NoshiPageDotsView *_dots;
    NoshiFlatButton *_button;
    UIButton *_qr;
    UIButton *_proxy;
    NSInteger _page;
    CGFloat _laidOutWidth;
    BOOL _visible;
    NoshiWelcomeToast *_toast;
    NoshiWelcomeToastKind _toastKind;
    BOOL _probing;
    /* the person closed the network card; it stays closed until the network has worked once and failed again */
    BOOL _networkDismissed;
    /* the card left because Telegram answered, which is not the person closing it */
    BOOL _leftForRecovery;
}
@end

@implementation NoshiWelcomeController

@synthesize delegate = _delegate;

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorBackdrop();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;

    _backdrop = [[NoshiWaveBackgroundView alloc] initWithFrame:root.bounds];
    _backdrop.animated = YES;
    [root addSubview:_backdrop];

    _scroll = [[UIScrollView alloc] initWithFrame:root.bounds];
    _scroll.pagingEnabled = YES;
    _scroll.bounces = NO;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.scrollsToTop = NO;
    /* ios 7 and 11 would inset the pages by the status bar and shift every offset */
    if ([self respondsToSelector:NSSelectorFromString(@"setAutomaticallyAdjustsScrollViewInsets:")]) {
        [self setValue:[NSNumber numberWithBool:NO] forKey:@"automaticallyAdjustsScrollViewInsets"];
    }
    if ([_scroll respondsToSelector:NSSelectorFromString(@"setContentInsetAdjustmentBehavior:")]) {
        [_scroll setValue:[NSNumber numberWithInteger:2] forKey:@"contentInsetAdjustmentBehavior"];
    }
    _scroll.delegate = self;
    [root addSubview:_scroll];

    _pages = [[NSMutableArray alloc] init];
    for (NSInteger i = 0; i < NOSHI_WELCOME_PAGES; ++i) {
        NoshiWelcomePage *page = [[[NoshiWelcomePage alloc] initWithIndex:i] autorelease];
        [_pages addObject:page];
        [_scroll addSubview:page];
    }

    _dots = [[NoshiPageDotsView alloc] init];
    _dots.pages = NOSHI_WELCOME_PAGES;
    [root addSubview:_dots];

    _button = [[NoshiFlatButton alloc] init];
    _button.title = NSLocalizedString(@"welcome.start", nil);
    [_button addTarget:self action:@selector(startTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_button];

    /* a plain line of text that does not compete with the button: half see-through until it is touched */
    _qr = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_qr setTitle:NSLocalizedString(@"phone.qr", nil) forState:UIControlStateNormal];
    [_qr setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    _qr.alpha = 0.6;
    [_qr addTarget:self action:@selector(qrTapped) forControlEvents:UIControlEventTouchUpInside];
    [_qr addTarget:self action:@selector(qrDown) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_qr addTarget:self action:@selector(qrUp)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [root addSubview:_qr];

    _proxy = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_proxy setTitle:NSLocalizedString(@"proxy.title", nil) forState:UIControlStateNormal];
    [_proxy setTitleColor:NoshiColorAccent() forState:UIControlStateNormal];
    _proxy.titleLabel.font = NoshiFontMedium(14);
    [_proxy addTarget:self action:@selector(proxyTapped) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_proxy];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self releaseToast];
    _scroll.delegate = nil;
    [_backdrop release];
    [_scroll release];
    [_pages release];
    [_dots release];
    [_button release];
    [_qr release];
    [_proxy release];
    [super dealloc];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return NoshiAllowsOrientation(orientation);
}

- (BOOL)shouldAutorotate {
    return YES;
}

/* the armv7 sdk declares this as NSUInteger and the arm64 sdk as the mask enum */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
- (NSUInteger)supportedInterfaceOrientations {
    return NoshiOrientationMask();
}
#pragma clang diagnostic pop

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size;
    UIEdgeInsets insets = NoshiLayoutInsets(self);
    /* a notch in landscape cuts into the sides, so the stack is laid out inside them */
    CGFloat side = insets.left;
    noshi_welcome_metrics metrics = {size.width - insets.left - insets.right, size.height, insets.top,
                                       insets.bottom, NoshiIsPad() ? 1 : 0, NOSHI_WELCOME_PAGES};
    noshi_welcome_layout layout;
    if (noshi_welcome_layout_compute(&metrics, &layout) != NOSHI_OK) {
        NSLog(@"noshigram: welcome layout does not fit %.0fx%.0f", size.width, size.height);
    }

    _backdrop.frame = self.view.bounds;
    _scroll.frame = self.view.bounds;
    _toast.inset = insets.top;
    [_toast refresh];
    /* both buttons stand on one line: the proxy is a taller touch area, so it is centered on the pill and not top aligned with it */
    _proxy.frame = CGRectMake(insets.left + 12, insets.top + 10, 88, 40);
    _scroll.contentSize = CGSizeMake(size.width * NOSHI_WELCOME_PAGES, size.height);
    for (NSInteger i = 0; i < NOSHI_WELCOME_PAGES; ++i) {
        NoshiWelcomePage *page = [_pages objectAtIndex:i];
        page.frame = CGRectMake(i * size.width, 0, size.width, size.height);
        page.art.frame = CGRectMake(side + layout.art.x, layout.art.y, layout.art.width, layout.art.height);
        page.title.frame = CGRectMake(side + layout.title.x, layout.title.y, layout.title.width, layout.title.height);
        page.title.font = NoshiFontBold(layout.title_size);
        page.message.frame = CGRectMake(side + layout.message.x, layout.message.y, layout.message.width, layout.message.height);
        page.message.font = NoshiFontRegular(layout.message_size);
        [page.message sizeToFit];
        CGRect fitted = page.message.frame;
        fitted.size.width = layout.message.width;
        fitted.origin.x = side + layout.message.x;
        fitted.size.height = MIN(fitted.size.height, layout.message.height);
        page.message.frame = fitted;
    }
    _dots.frame = CGRectMake(side + layout.dots.x, layout.dots.y, layout.dots.width, layout.dots.height);
    _dots.diameter = (CGFloat)layout.dot_diameter;
    _button.frame = CGRectMake(side + layout.button.x, layout.button.y, layout.button.width, layout.button.height);
    _button.cornerRadius = (CGFloat)layout.button_radius;
    _button.titleSize = (CGFloat)layout.button_size;
    /* the link goes under the button, or over it when the button sits too low for a line beneath */
    CGFloat linkHeight = 36;
    CGFloat below = CGRectGetMaxY(_button.frame) + 6;
    BOOL fits = below + linkHeight <= size.height - insets.bottom - 2;
    _qr.titleLabel.font = NoshiFontMedium(16);
    _qr.frame = CGRectMake(_button.frame.origin.x, fits ? below : _button.frame.origin.y - linkHeight - 6, _button.frame.size.width, linkHeight);

    /* rotation changes the page width, and the offset would otherwise keep the old pixel position */
    if (size.width != _laidOutWidth) {
        _laidOutWidth = size.width;
        _scroll.contentOffset = CGPointMake(_page * size.width, 0);
    }
    [_dots setProgress:noshi_pager_progress(_scroll.contentOffset.x, size.width, NOSHI_WELCOME_PAGES)];
}

- (void)proxyTapped {
    noshi_proxy proxy;
    BOOL enabled = NO;
    noshi_status status = NoshiProxyRead(&proxy, &enabled);
    noshi_wipe(&proxy, sizeof(proxy));
    if (status != NOSHI_OK && !enabled) NSLog(@"noshigram: proxy settings unavailable: %s", noshi_status_name(status));
    NSArray *choices = [NSArray arrayWithObjects:NSLocalizedString(@"proxy.add", nil), NSLocalizedString(enabled ? @"proxy.disable" : @"proxy.enable", nil), nil];
    NoshiChoose(NSLocalizedString(@"proxy.title", nil), choices, -1, ^(NSInteger index) {
        if (index == 0) {
            NoshiPromptText(NSLocalizedString(@"proxy.add", nil), nil, nil, NSLocalizedString(@"proxy.link.hint", nil), ^(NSString *text) {
                if (!text.length) return;
                noshi_status saved = NoshiProxyStoreLink([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
                if (saved != NOSHI_OK) NoshiShowNotice(NSLocalizedString(@"proxy.title", nil), NSLocalizedString(saved == NOSHI_E_STORAGE ? @"proxy.savefailed" : @"proxy.invalid", nil));
            });
        } else if (index == 1) {
            noshi_status changed = NoshiProxySetEnabled(!enabled);
            if (changed != NOSHI_OK) NoshiShowNotice(NSLocalizedString(@"proxy.title", nil), NSLocalizedString(@"proxy.invalid", nil));
        }
    });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _visible = YES;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(refreshPlayback)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
    NSString *motion = NoshiReduceMotionChangedNotification();
    if (motion) [center addObserver:self selector:@selector(refreshPlayback) name:motion object:nil];
    [center addObserver:self selector:@selector(probeNetwork) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self refreshPlayback];
    [self probeNetwork];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    /* the next screen has no use for a card of this one, and its buttons act on this screen */
    [self releaseToast];
    [self refreshPlayback];
}

/* backgrounding drops running core animations, so the active page starts again on return */
- (void)refreshPlayback {
    for (NSInteger i = 0; i < NOSHI_WELCOME_PAGES; ++i) {
        UIView *art = ((NoshiWelcomePage *)[_pages objectAtIndex:i]).art;
        BOOL active = _visible && i == _page;
        /* the first page shows the still icon of the app, the others play their stickers */
        if (![art isKindOfClass:[NoshiLottieView class]]) continue;
        NoshiLottieView *sticker = (NoshiLottieView *)art;
        [sticker setLoaded:ABS(i - _page) <= 1];
        [sticker setPlaying:active];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat width = scrollView.bounds.size.width;
    [_dots setProgress:noshi_pager_progress(scrollView.contentOffset.x, width, NOSHI_WELCOME_PAGES)];
    NSInteger page = noshi_pager_page(scrollView.contentOffset.x, width, NOSHI_WELCOME_PAGES);
    /* layout resets the offset on rotation; that is not a page change */
    if (page == _page || width != _laidOutWidth) return;
    _page = page;
    [self refreshPlayback];
}

- (void)qrTapped {
    [_delegate welcomeControllerDidRequestQr:self];
}

- (void)qrDown {
    _qr.alpha = 0.3;
}

- (void)qrUp {
    [UIView animateWithDuration:0.2 animations:^{ _qr.alpha = 0.6; }];
}

- (void)startTapped {
    [_delegate welcomeControllerDidTapStart:self];
}

#pragma mark cards

/* the card is owned here and its handlers hold this screen only weakly, so neither keeps the other alive */
- (void)releaseToast {
    [NSObject cancelPreviousPerformRequestsWithTarget:_toast];
    _toast.primaryHandler = nil;
    _toast.secondaryHandler = nil;
    _toast.dismissHandler = nil;
    [_toast removeFromSuperview];
    [_toast release];
    _toast = nil;
    _toastKind = NoshiWelcomeToastNone;
}

- (void)presentToast:(NoshiWelcomeToast *)toast kind:(NoshiWelcomeToastKind)kind {
    [self releaseToast];
    _toast = [toast retain];
    _toastKind = kind;
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
    toast.dismissHandler = ^{
        NoshiWelcomeController *me = weak.target;
        if (!me) return;
        NoshiWelcomeToastKind left = me->_toastKind;
        BOOL recovered = me->_leftForRecovery;
        me->_leftForRecovery = NO;
        [me releaseToast];
        if (left >= NoshiWelcomeToastNoLink && !recovered) me->_networkDismissed = YES;
    };
    [toast showInView:self.view inset:NoshiLayoutInsets(self).top];
}

- (void)fillNetworkToast:(NoshiWelcomeToast *)toast {
    toast.busyTitle = nil;
    toast.titleText = NSLocalizedString(@"welcome.network.nolink.title", nil);
    toast.messageText = NSLocalizedString(@"welcome.network.nolink.message", nil);
    toast.primaryTitle = NSLocalizedString(@"welcome.network.retry", nil);
    toast.secondaryTitle = NSLocalizedString(@"welcome.network.close", nil);
}

- (void)networkPrimaryTapped {
    [self probeNetwork];
    if (_toast) {
        _toast.busyTitle = NSLocalizedString(@"welcome.network.checking", nil);
        [_toast refresh];
    }
}

- (void)networkSecondaryTapped {
    [_toast dismiss];
}

/* a card already on screen says it again, with the busy words of a retry taken away */
- (void)syncNetworkToast {
    if (!_toast || _toastKind != NoshiWelcomeToastNoLink) return;
    [self fillNetworkToast:_toast];
    [_toast refresh];
}

- (void)showNetworkToast {
    if (!_visible || _networkDismissed) return;
    if (_toast && _toastKind == NoshiWelcomeToastNoLink) {
        [self syncNetworkToast];
        return;
    }
    /* the greeting makes way: it is only a thank-you, and the person cannot sign in yet */
    if (_toast) {
        [_toast dismiss];
        [self performSelector:@selector(showNetworkToast) withObject:nil afterDelay:0.35];
        return;
    }
    NoshiWelcomeToast *toast = [[[NoshiWelcomeToast alloc] init] autorelease];
    NoshiLottieView *sticker = [[[NoshiLottieView alloc] initWithAnimationNamed:NETWORK_STICKER] autorelease];
    toast.sticker = sticker;
    [self fillNetworkToast:toast];
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
    toast.primaryHandler = ^{ [(NoshiWelcomeController *)weak.target networkPrimaryTapped]; };
    toast.secondaryHandler = ^{ [(NoshiWelcomeController *)weak.target networkSecondaryTapped]; };
    [self presentToast:toast kind:NoshiWelcomeToastNoLink];
}

#pragma mark network

/* asks whether Telegram can be reached; the screen has no session to tell it */
- (void)probeNetwork {
    if (_probing || !_visible) return;
    _probing = YES;
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
    [NoshiNetworkProbe probeWithCompletion:^(NoshiProbeResult result) {
        NoshiWelcomeController *me = weak.target;
        if (!me) return;
        me->_probing = NO;
        [me probeFinished:result];
    }];
}

- (void)probeFinished:(NoshiProbeResult)result {
    if (!_visible) return;
    switch (result) {
    case NoshiProbeReachable:
        _networkDismissed = NO;
        if (_toast && _toastKind == NoshiWelcomeToastNoLink) {
            _leftForRecovery = YES;
            [_toast dismiss];
        }
        break;
    case NoshiProbeUnreachable:
        [self showNetworkToast];
        break;
    }
}

@end

#import "noshi_main_controller.h"
#import "noshi_back_swipe.h"
#import "noshi_accounts.h"
#import "noshi_popup_menu.h"
#import "noshi_chat_settings.h"

#import "noshi_classic_calls_controller.h"
#import "noshi_classic_chats_controller.h"
#import "noshi_classic_chrome.h"
#import "noshi_classic_contacts_controller.h"
#import "noshi_classic_profile_controller.h"
#import "noshi_chat_controller.h"
#import "noshi_community_screen.h"
#import "noshi_topics_screen.h"
#import "noshi_language.h"
#import "noshi_lite_mode.h"
#import "noshi_link_router.h"
#import "noshi_dialog_picker_controller.h"
#import "noshi_gift_screen.h"
#import "noshi_share_intake.h"
#import "noshi_weak_reference.h"
#import "noshi_notifier.h"
#import "noshi_person.h"
#import "noshi_platform.h"
#import "noshi_settings_controller.h"
#import "noshi_settings_kit.h"
#import "noshi_split_controller.h"
#import "noshi_theme.h"
#import "noshi_theme_busy_view.h"
#import "noshi_wave_background_view.h"

#import <QuartzCore/QuartzCore.h>

/* what a tab of the bar shows; the layout of the person puts four of these in a row */
enum {
    NoshiTabChats = NOSHI_TAB_CHATS,
    NoshiTabContacts = NOSHI_TAB_CONTACTS,
    NoshiTabSettings = NOSHI_TAB_SETTINGS,
    NoshiTabProfile = NOSHI_TAB_PROFILE,
    NoshiTabCalls = NOSHI_TAB_CALLS
};
#define NoshiTabCount NOSHI_TAB_SLOTS

/* the four tabs of a layout, in the order of the bar */
static void NoshiTabKinds(NoshiTabLayout layout, NSInteger kinds[NoshiTabCount]) {
    int order[NOSHI_TAB_SLOTS];
    (void)layout;
    NoshiTabOrderLoad(order);
    for (NSUInteger i = 0; i < NOSHI_TAB_SLOTS; ++i) kinds[i] = order[i];
}

static NSInteger NoshiTabIndexOfKind(const NSInteger kinds[NoshiTabCount], NSInteger kind) {
    for (NSInteger i = 0; i < NoshiTabCount; ++i) if (kinds[i] == kind) return i;
    return -1;
}

static NSString *NoshiTabTitle(NSInteger kind) {
    static NSString *const keys[] = {@"tab.chats", @"tab.contacts", @"tab.settings", @"tab.profile", @"tab.calls"};
    return NSLocalizedString(keys[kind], nil);
}

static NoshiSymbol NoshiTabSymbol(NSInteger kind) {
    static const NoshiSymbol symbols[] = {NoshiSymbolChats, NoshiSymbolPerson, NoshiSymbolGear, NoshiSymbolSmiley, NoshiSymbolPhone};
    return symbols[kind];
}

#define CLASSIC_BADGE_TAG 0x4258

/* the count sits on the right of the first icon, whatever the width of the bar after a rotation */
static void NoshiPlaceClassicBadge(UITabBar *bar, CGFloat width, NSInteger index) {
    UIView *badge = [bar viewWithTag:CLASSIC_BADGE_TAG];
    if (!badge) return;
    badge.frame = CGRectMake(floor(width * (CGFloat)(2 * index + 1) / (CGFloat)(NoshiTabCount * 2)) + 4, 1, badge.frame.size.width, badge.frame.size.height);
}

@interface NoshiMainController () <UITabBarControllerDelegate, UINavigationControllerDelegate, UIGestureRecognizerDelegate> {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    NoshiLinkRouter *_linkRouter;
    UIViewController *_current;
    UITabBarController *_classicTabs;
    /* the tab that wears the profile photo in the classic bar; the tab controller owns it */
    UITabBarItem *_classicProfileItem;
    /* the swipe back of each classic tab: the tabs push into their own navigation controllers, which the one on the window never sees */
    NSMutableArray *_classicBackSwipes;
    UIImageView *_veil;
    NoshiThemeBusyView *_busy;
    BOOL _busyShown;
    CGPoint _revealOrigin;
    /* the kinds of the tabs the bar was built with, so a change of layout knows which tab the person stood on */
    NSInteger _kinds[NoshiTabCount];
}
@end

@implementation NoshiMainController

@synthesize delegate = _delegate;
@synthesize detailHost = _detailHost;

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    /* child bars own the status area, ios 5 must not reserve it again in each container */
    self.wantsFullScreenLayout = YES;
    _session = [session retain];
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *root = [caches stringByAppendingPathComponent:@"Noshigram"];
    _avatars = [[NoshiAvatarCache alloc] initWithSession:session directory:[root stringByAppendingPathComponent:@"avatars"]];
    _media = [[NoshiMediaCache alloc] initWithSession:session directory:[root stringByAppendingPathComponent:@"media"]];
    /* the files past the days the person chose to keep them go when the screens start */
    [_media removeFilesOlderThanDays:NoshiCacheKeepDays()];
    _stickers = [[NoshiStickerLibrary alloc] initWithSession:session];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_veil removeFromSuperview];
    [_veil release];
    [_busy stopAnimating];
    [_busy removeFromSuperview];
    [_busy release];
    [self releaseContent];
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    _linkRouter.anchor = nil;
    [_linkRouter release];
    [super dealloc];
}

/* the screens and the bar go together, so the theme change can build both again */
- (void)releaseContent {
    /* the handlers capture this controller */
    for (UINavigationController *navigation in _classicTabs.viewControllers) {
        id root = navigation.viewControllers.count ? [navigation.viewControllers objectAtIndex:0] : nil;
        if ([root respondsToSelector:@selector(setSignOutHandler:)]) [root setSignOutHandler:nil];
        if (navigation.delegate == (id)self) navigation.delegate = nil;
    }
    [_classicBackSwipes release];
    _classicBackSwipes = nil;
    [_classicTabs willMoveToParentViewController:nil];
    [_classicTabs.view removeFromSuperview];
    [_classicTabs removeFromParentViewController];
    [_classicTabs release];
    _classicTabs = nil;
    _classicProfileItem = nil;
}

- (void)loadView {
    UIView *root = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    root.backgroundColor = NoshiColorScreen();
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
    /* the busy view draws its duck into pictures when it is made, and the first change of the theme should find them done */
    [self performSelector:@selector(prepareBusy) withObject:nil afterDelay:3];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:)
                                                 name:NoshiThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tabOrderChanged:)
                                                 name:NoshiTabOrderDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageChanged)
                                                 name:NoshiLanguageDidChangeNotification object:nil];
    [self buildContentWithTab:-1];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ownProfileChanged) name:NoshiOwnProfileDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openChatRequested:) name:NoshiOpenChatNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openLinkRequested:) name:NoshiOpenLinkNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shareFilesRequested:) name:NoshiShareFilesNotification object:nil];
}

/* files handed over by the share sheet: the person picks the chat they go to, and the chat opens once they are sent */
- (void)shareFilesRequested:(NSNotification *)note {
    NSArray *urls = [note.userInfo objectForKey:@"urls"];
    NSString *text = [note.userInfo objectForKey:@"text"];
    NSString *directory = [note.userInfo objectForKey:@"directory"];
    if (![urls isKindOfClass:[NSArray class]] || (!urls.count && !text.length)) return;
    NoshiDialogPickerController *picker = [[[NoshiDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"share.to", nil);
    picker.forwarding = YES;
    picker.filter = ^BOOL(NoshiDialog *dialog) {
        return !dialog.folder && !dialog.community && (dialog.kind != NOSHI_DIALOG_CHANNEL || dialog.canPost);
    };
    NoshiWeakReference *weak = [NoshiWeakReference referenceTo:self];
    picker.pickHandler = ^(NSArray *dialogs) {
        NoshiMainController *main = weak.target;
        NoshiDialog *target = [dialogs lastObject];
        if (!main || !target) return;
        NoshiShareSendFiles(urls, text, target, main->_session, ^(NSString *errorName) {
            NoshiShareDiscard(directory);
            NoshiMainController *again = weak.target;
            if (errorName) NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            if (again) [again openDialog:target];
        });
    };
    UINavigationController *navigation = _classicTabs ? (UINavigationController *)_classicTabs.selectedViewController : self.navigationController;
    if (_classicTabs) [navigation popToRootViewControllerAnimated:NO];
    else [navigation popToViewController:self animated:NO];
    [navigation pushViewController:picker animated:YES];
}

/* an address from outside the screens: it opens over the tab that is up, as a tap on it inside a chat would */
- (void)openLinkRequested:(NSNotification *)note {
    NSString *url = [note.userInfo objectForKey:@"url"];
    if (![url isKindOfClass:[NSString class]] || !url.length) return;
    if (!_linkRouter) _linkRouter = [[NoshiLinkRouter alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers];
    UIViewController *anchor = self;
    if (_classicTabs) anchor = [(UINavigationController *)_classicTabs.selectedViewController topViewController];
    _linkRouter.anchor = anchor;
    [_linkRouter openLink:url];
}

/* a notification was tapped: the chat opens over the list, whichever screen was up */
- (void)openChatRequested:(NSNotification *)note {
    int32_t kind = (int32_t)[[note.userInfo objectForKey:@"kind"] intValue];
    long long peer = [[note.userInfo objectForKey:@"peer"] longLongValue];
    [self retain];
    [_session loadDialogs:^(NSArray *items, NSString *errorName) {
        [self autorelease];
        if (!items) {
            NSLog(@"noshigram: the chat of the notification could not be looked up: %@", errorName);
            return;
        }
        for (NoshiDialog *dialog in items) {
            if (!dialog.folder && dialog.peerKind == kind && dialog.peerId == peer) {
                [self openDialog:dialog];
                return;
            }
        }
        NSLog(@"noshigram: the chat %lld of the notification is not in the list", peer);
    }];
}

- (void)openDialog:(NoshiDialog *)dialog {
    UIViewController *chat = dialog.community ? NoshiCommunityScreen(_session, dialog, nil, _avatars, _media, _stickers, nil)
        : dialog.forum ? NoshiTopicsScreen(_session, dialog, _avatars, _media, _stickers, nil)
        : [[[NoshiChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media stickers:_stickers] autorelease];
    if (_classicTabs) {
        _classicTabs.selectedIndex = (NSUInteger)MAX(0, NoshiTabIndexOfKind(_kinds, NoshiTabChats));
        UINavigationController *navigation = (UINavigationController *)_classicTabs.selectedViewController;
        [navigation popToRootViewControllerAnimated:NO];
        [navigation pushViewController:chat animated:NO];
        return;
    }
    [self.navigationController popToViewController:self animated:NO];
    [self.navigationController pushViewController:chat animated:NO];
}

/* the classic style is the system's own tab bar over navigation controllers, each with a navigation bar of its own; the
   screens are built when the tab bar is, since it asks each of them for its title at once */
- (void)buildClassicWithTab:(NSInteger)tab {
    NoshiClassicChatsController *chats = nil;
    NSMutableArray *screens = [NSMutableArray array], *navigations = [NSMutableArray array];
    for (NSInteger i = 0; i < NoshiTabCount; ++i) {
        UIViewController *screen = nil;
        switch (_kinds[i]) {
        case NoshiTabChats:
            chats = [[[NoshiClassicChatsController alloc] initWithSession:_session folderId:0 avatars:_avatars media:_media stickers:_stickers] autorelease];
            screen = chats;
            break;
        case NoshiTabContacts:
            screen = [[[NoshiClassicContactsController alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers] autorelease];
            break;
        case NoshiTabCalls:
            screen = [[[NoshiClassicCallsController alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers] autorelease];
            break;
        case NoshiTabSettings: {
            /* the settings are one screen in both styles: the grouped table draws the same sections the modern cards do */
            NoshiSettingsController *settings = [[[NoshiSettingsController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
            settings.signOutHandler = ^(void (^completion)(NSString *errorName)) { [_delegate mainController:self requestsSignOut:completion]; };
            screen = settings;
            break;
        }
        default: {
            NoshiClassicProfileController *profile = [[[NoshiClassicProfileController alloc] initWithSession:_session avatars:_avatars] autorelease];
            profile.media = _media;
            profile.stickerLibrary = _stickers;
            profile.signOutHandler = ^(void (^completion)(NSString *errorName)) { [_delegate mainController:self requestsSignOut:completion]; };
            screen = profile;
            break;
        }
        }
        [screens addObject:screen];
    }
    for (NSUInteger i = 0; i < screens.count; ++i) {
        NoshiSymbol symbol = NoshiTabSymbol(_kinds[i]);
        UINavigationController *navigation = [[[NoshiSplitNavigationController alloc] initWithRootViewController:[screens objectAtIndex:i]] autorelease];
        [(NoshiSplitNavigationController *)navigation setDetailHost:_detailHost];
        NoshiClassicStyleNavigationBar(navigation.navigationBar);
        /* the strip of the song comes and goes with the screens a tab pushes */
        navigation.delegate = self;
        NoshiBackSwipe *backSwipe = [[NoshiBackSwipe alloc] initWithNavigationController:navigation];
        if (!_classicBackSwipes) _classicBackSwipes = [[NSMutableArray alloc] init];
        [_classicBackSwipes addObject:backSwipe];
        [backSwipe release];
        navigation.tabBarItem = [[[UITabBarItem alloc] initWithTitle:NoshiTabTitle(_kinds[i]) image:NoshiClassicTabImage(symbol) tag:(NSInteger)i] autorelease];
        NoshiClassicStyleTabItem(navigation.tabBarItem, symbol);
        [navigations addObject:navigation];
    }
    _classicTabs = [[UITabBarController alloc] init];
    _classicTabs.wantsFullScreenLayout = YES;
    _classicTabs.delegate = self;
    _classicTabs.viewControllers = navigations;
    _classicTabs.selectedIndex = (NSUInteger)tab;
    NoshiClassicStyleTabBar(_classicTabs.tabBar);
    /* the system badge is red on ios 5 to 9 and takes no color before ios 10, so the count is a label of our own in the accent */
    UITabBar *bar = _classicTabs.tabBar;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(classicBarHeld:)];
    [bar addGestureRecognizer:hold];
    [hold release];
    chats.unreadHandler = ^(NSInteger total) {
        [[bar viewWithTag:CLASSIC_BADGE_TAG] removeFromSuperview];
        if (total <= 0) return;
        UILabel *badge = NoshiClassicBadge(total > 999 ? @"999+" : [NSString stringWithFormat:@"%ld", (long)total], NO);
        badge.tag = CLASSIC_BADGE_TAG;
        badge.userInteractionEnabled = NO;
        [bar addSubview:badge];
        NoshiPlaceClassicBadge(bar, bar.bounds.size.width, NoshiTabIndexOfKind(_kinds, NoshiTabChats));
    };
    [self addChildViewController:_classicTabs];
    _classicTabs.view.frame = self.view.bounds;
    _classicTabs.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_classicTabs.view];
    [_classicTabs didMoveToParentViewController:self];
    /* the profile tab, when the layout has one, wears the profile photo once it is here */
    NSInteger profileIndex = NoshiTabIndexOfKind(_kinds, NoshiTabProfile);
    if (profileIndex < 0) return;
    _classicProfileItem = ((UIViewController *)[navigations objectAtIndex:(NSUInteger)profileIndex]).tabBarItem;
    [self loadClassicProfileTab];
}

/* a tab picture drawn from the photo, or the symbol of the tab again when the person has none (the photo was removed) */
- (void)showClassicProfilePhoto:(UIImage *)photo onItem:(UITabBarItem *)item {
    if (![item respondsToSelector:@selector(setFinishedSelectedImage:withFinishedUnselectedImage:)]) return;
    if (!photo) {
        /* nil takes the finished pictures away, and the plain tab picture the item was made with shows again */
        [item setFinishedSelectedImage:nil withFinishedUnselectedImage:nil];
        return;
    }
    UIImage *tab = NoshiClassicProfileTabImage(photo);
    [item setFinishedSelectedImage:tab withFinishedUnselectedImage:tab];
}

- (void)loadClassicProfileTab {
    UITabBarItem *profileItem = _classicProfileItem;
    if (!profileItem) return;
    /* the photo of the last time is on the tab before the answer comes */
    NoshiPerson *known = [_session ownPerson];
    if (known.photo) {
        [_avatars pinPhoto:known.photo];
        [_avatars loadImageForPhoto:known.photo completion:^(UIImage *photo) {
            if (photo && profileItem == _classicProfileItem) [self showClassicProfilePhoto:photo onItem:profileItem];
        }];
    }
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        if (!items) {
            NSLog(@"noshigram: profile tab did not load: %@", errorName);
            return;
        }
        NoshiPerson *person = [items objectAtIndex:0];
        [_avatars pinPhoto:person.photo];
        /* the account list shows this face when the account is not the one in use, and then has no connection to ask for it */
        NoshiAccountKeepPhotoOfPerson(person, _avatars);
        NoshiLiteSetPremium(NoshiPremiumEffective(person.premium));
        if (profileItem != _classicProfileItem) return;
        if (!person.photo) {
            [self showClassicProfilePhoto:nil onItem:profileItem];
            return;
        }
        [_avatars loadImageForPhoto:person.photo completion:^(UIImage *photo) {
            if (photo && profileItem == _classicProfileItem) [self showClassicProfilePhoto:photo onItem:profileItem];
        }];
    }];
}

/* the photo of the account was set or removed: the tab that wears it is asked for again, since it is made once when the bar is */
- (void)ownProfileChanged {
    if (_classicTabs) [self loadClassicProfileTab];
}

/* the system tab bar swaps its screens at once; a push transition on the container of the screens, not on the bar, gives the same
   sideways slide the modern tabs have */
- (BOOL)tabBarController:(UITabBarController *)tabs shouldSelectViewController:(UIViewController *)screen {
    NSUInteger from = tabs.selectedIndex, to = [tabs.viewControllers indexOfObject:screen];
    if (from == to && to < NoshiTabCount && _kinds[to] == NoshiTabChats && [screen isKindOfClass:[UINavigationController class]]) {
        /* the system pops a tab that is reselected to its root by itself; at the root there is nothing to pop, so the list goes up */
        UINavigationController *navigation = (UINavigationController *)screen;
        id root = navigation.viewControllers.count ? [navigation.viewControllers objectAtIndex:0] : nil;
        if (navigation.viewControllers.count == 1 && [root isKindOfClass:[NoshiClassicChatsController class]]) [(NoshiClassicChatsController *)root scrollToTopAnimated];
    }
    if (from == to || to == NSNotFound) return YES;
    for (UIView *container in tabs.view.subviews) {
        if ([container isKindOfClass:[UITabBar class]]) continue;
        /* ios 6 fills the clear corners of the bar with black in the snapshot of a push transition when the container has no opaque color */
        tabs.view.backgroundColor = NoshiColorScreen();
        container.backgroundColor = NoshiColorScreen();
        CATransition *slide = [CATransition animation];
        slide.type = kCATransitionPush;
        slide.subtype = to > from ? kCATransitionFromRight : kCATransitionFromLeft;
        slide.duration = 0.3;
        slide.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [container.layer addAnimation:slide forKey:@"tab"];
        break;
    }
    return YES;
}

/* tab is the place in the bar to land on, or -1 for the chats */
- (void)buildContentWithTab:(NSInteger)tab {
    NoshiTabKinds(NoshiTabLayoutStored(), _kinds);
    if (tab < 0 || tab >= NoshiTabCount) tab = MAX(0, NoshiTabIndexOfKind(_kinds, NoshiTabChats));
    [self buildClassicWithTab:tab];
}

- (void)prepareBusy {
    if (_busy) return;
    _busy = [[NoshiThemeBusyView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
}

/* the root view turns with the interface on ios 5 through 7 */
- (UIView *)themeHost {
    return NoshiOverlayHost();
}

- (void)themeChanged:(NSNotification *)note {
    NSValue *origin = [note.userInfo objectForKey:NoshiThemeOriginKey];
    UIView *host = [self themeHost];
    _revealOrigin = [origin isKindOfClass:[NSValue class]] && host ? [host convertPoint:[origin CGPointValue] fromView:nil] : CGPointMake(-1, -1);
    [self coverWithSnapshot];
    [self showBusyOverVeil];
}

- (void)tabOrderChanged:(NSNotification *)note {
    (void)note;
    NSArray *pages = [self pagesToRestore];
    BOOL wasClassic = _classicTabs != nil;
    [self rebuildContent];
    [self restorePages:pages wasClassic:wasClassic];
}

/* the old screen darkens a little and the duck paints while the screens are made again, which keeps the main
   thread busy and would otherwise look like a freeze */
- (void)showBusyOverVeil {
    UIView *window = [self themeHost];
    if (!window || !_veil || _busyShown) {
        [self performSelector:@selector(rebuildForTheme) withObject:nil afterDelay:0];
        return;
    }
    /* the view and its parsed duck are kept from one change to the next: the first change would otherwise wait for the parse */
    if (!_busy) _busy = [[NoshiThemeBusyView alloc] initWithFrame:window.bounds];
    _busyShown = YES;
    _busy.frame = window.bounds;
    _busy.alpha = NoshiReduceMotionEnabled() ? 1 : 0;
    [window addSubview:_busy];
    [_busy startAnimating];
    [self retain];
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.22 animations:^{ _busy.alpha = 1; } completion:^(BOOL finished) {
        (void)finished;
        [_busy whenReady:^{
            [self rebuildForTheme];
            [self autorelease];
        }];
    }];
}

/* the circle of the new colors opens over the picture, and the darkening and the duck go as it spreads */
- (void)dismissBusy {
    if (!_busyShown) return;
    _busyShown = NO;
    NoshiThemeBusyView *busy = _busy;
    /* the view is kept, so UIKit never reads one that is gone after the animation */
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.3 animations:^{ busy.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        if (_busyShown) return;
        [busy stopAnimating];
        [busy removeFromSuperview];
    }];
}

static void NoshiCollectWaves(UIView *view, NSMutableArray *waves) {
    if ([view isKindOfClass:[NoshiWaveBackgroundView class]]) [waves addObject:view];
    for (UIView *child in view.subviews) NoshiCollectWaves(child, waves);
}

/* the old screen stays above the rebuild as a picture, so the swap never shows a half built tab bar */
- (void)coverWithSnapshot {
    UIView *window = [self themeHost];
    if (!window || _veil) return;
    /* the waves are masked layers, which a picture of the window does not draw; they draw themselves for it */
    NSMutableArray *waves = [NSMutableArray array];
    NoshiCollectWaves(window, waves);
    for (NoshiWaveBackgroundView *wave in waves) [wave beginSnapshot];
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 0);
    [window.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *picture = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    for (NoshiWaveBackgroundView *wave in waves) [wave endSnapshot];
    _veil = [[UIImageView alloc] initWithImage:picture];
    _veil.frame = window.bounds;
    _veil.userInteractionEnabled = YES;
    [window addSubview:_veil];
}

/* a circle of the new theme grows from the settings switch and eats the picture of the old one */
- (void)revealBehindVeil {
    UIImageView *veil = _veil;
    _veil = nil;
    [self dismissBusy];
    if (!veil) return;
    CGRect bounds = veil.bounds;
    /* the screen that asked for the change says where it was touched; the switch of the settings tab asks without a point */
    CGPoint origin = _revealOrigin.x >= 0 ? _revealOrigin : CGPointMake(bounds.size.width - 48, 150);
    CGFloat reach = hypot(MAX(origin.x, bounds.size.width - origin.x), MAX(origin.y, bounds.size.height - origin.y));
    CGPathRef (^hole)(CGFloat) = ^CGPathRef(CGFloat radius) {
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathAddRect(path, NULL, bounds);
        CGPathAddEllipseInRect(path, NULL, CGRectMake(origin.x - radius, origin.y - radius, 2 * radius, 2 * radius));
        return path;
    };
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = bounds;
    mask.fillRule = kCAFillRuleEvenOdd;
    CGPathRef from = hole(0.01), to = hole(reach);
    mask.path = to;
    veil.layer.mask = mask;
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.6];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [CATransaction setCompletionBlock:^{
        [veil removeFromSuperview];
        [veil release];
    }];
    CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"path"];
    grow.fromValue = (id)from;
    grow.toValue = (id)to;
    [mask addAnimation:grow forKey:@"reveal"];
    [CATransaction commit];
    CGPathRelease(from);
    CGPathRelease(to);
}

/* the texts are read when a view is built, so a new language needs new screens too */
- (void)languageChanged {
    [self coverWithSnapshot];
    [self performSelector:@selector(rebuildForLanguage) withObject:nil afterDelay:0];
}

- (void)fadeOutVeil {
    UIImageView *veil = _veil;
    _veil = nil;
    if (!veil) return;
    [UIView animateWithDuration:NoshiReduceMotionEnabled() ? 0 : 0.25 animations:^{ veil.alpha = 0; } completion:^(BOOL finished) {
        (void)finished;
        [veil removeFromSuperview];
        /* UIKit still reads the view after its completion block returns, so the last reference goes at the end of the pass and not here */
        [veil autorelease];
    }];
}

- (void)rebuildForLanguage {
    [self rebuildContent];
    [self fadeOutVeil];
}

/* colors are read when a view is built, so a new palette needs new screens; the settings tab is built again
   and shown, because the person is standing on it */
- (void)rebuildForTheme {
    NSArray *pages = [self pagesToRestore];
    BOOL wasClassic = _classicTabs != nil;
    [self rebuildContent];
    [self restorePages:pages wasClassic:wasClassic];
    /* the right pane rebuilds its own pages after the new style is active */
    [_detailHost styleDidChange:wasClassic || _classicTabs != nil];
    [self revealBehindVeil];
}

/* the pages pushed over the tab the person stands on */
- (NSArray *)pagesToRestore {
    if (_detailHost) return nil;
    UINavigationController *navigation = _classicTabs ? (UINavigationController *)_classicTabs.selectedViewController : self.navigationController;
    NSArray *all = navigation.viewControllers;
    NSUInteger from = _classicTabs ? 1 : [all indexOfObjectIdenticalTo:self] + 1;
    if (from == 0 || from >= all.count) return nil;
    return [NSArray arrayWithArray:[all subarrayWithRange:NSMakeRange(from, all.count - from)]];
}

/* the pages are made again after the screens, so they read the new colors */
- (void)restorePages:(NSArray *)pages wasClassic:(BOOL)wasClassic {
    if (!pages.count) return;
    if (!wasClassic) [self.navigationController popToViewController:self animated:NO];
    UINavigationController *navigation = _classicTabs ? (UINavigationController *)_classicTabs.selectedViewController : self.navigationController;
    for (UIViewController *old in pages) {
        if (![old respondsToSelector:@selector(controllerAfterThemeChange)]) break;
        UIViewController *again = [(id<NoshiThemeRestorable>)old controllerAfterThemeChange];
        if (!again) break;
        [navigation pushViewController:again animated:NO];
    }
}

- (void)rebuildContent {
    /* the person stays on the tab they were on, which is settings when the switch there made the change */
    NSInteger tab = _classicTabs ? (NSInteger)_classicTabs.selectedIndex : 0;
    /* a new layout may put the tab somewhere else, or have none of that kind: the settings are where the change was made, so they are the fallback */
    NSInteger kind = tab >= 0 && tab < NoshiTabCount ? _kinds[tab] : NoshiTabSettings;
    NSInteger next[NoshiTabCount];
    NoshiTabKinds(NoshiTabLayoutStored(), next);
    tab = NoshiTabIndexOfKind(next, kind);
    if (tab < 0) tab = NoshiTabIndexOfKind(next, NoshiTabSettings);
    NoshiThemeApplyStored();
    if (_current) {
        [_current willMoveToParentViewController:nil];
        [_current beginAppearanceTransition:NO animated:NO];
        [_current.view removeFromSuperview];
        [_current endAppearanceTransition];
        [_current removeFromParentViewController];
        _current = nil;
    }
    [self releaseContent];
    self.view.backgroundColor = NoshiColorScreen();
    [self buildContentWithTab:tab];
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
    if (_classicTabs) {
        NoshiClassicNoteTabBarHeight(_classicTabs.tabBar.frame.size.height);
        NoshiPlaceClassicBadge(_classicTabs.tabBar, self.view.bounds.size.width, NoshiTabIndexOfKind(_kinds, NoshiTabChats));
    }
}

- (void)tabBarController:(UITabBarController *)tabs didSelectViewController:(UIViewController *)screen {
    (void)tabs; (void)screen;
    [self.view setNeedsLayout];
}

- (void)navigationController:(UINavigationController *)navigation willShowViewController:(UIViewController *)screen animated:(BOOL)animated {
    (void)navigation; (void)screen; (void)animated;
    [self.view setNeedsLayout];
}

- (void)navigationController:(UINavigationController *)navigation didShowViewController:(UIViewController *)screen animated:(BOOL)animated {
    (void)navigation; (void)screen; (void)animated;
    [self.view setNeedsLayout];
}

#pragma mark delegates

/* the system tab bar has no hold of its own: a finger held on the slot of the profile tab offers the accounts of the phone, as the official client does */
- (void)classicBarHeld:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan || !_classicTabs) return;
    UIView *bar = hold.view;
    CGFloat slot = bar.bounds.size.width / (CGFloat)NoshiTabCount;
    NSInteger index = (NSInteger)floor([hold locationInView:bar].x / slot);
    if (index < 0 || index >= NoshiTabCount || _kinds[index] != NoshiTabProfile) return;
    [self showAccountsAboveBar:bar frame:CGRectMake(slot * (CGFloat)index, 0, slot, bar.bounds.size.height)];
}

- (void)showAccountsAboveBar:(UIView *)tabBar frame:(CGRect)frame {
    NSString *active = NoshiAccountActive();
    NSMutableArray *titles = [NSMutableArray array], *names = [NSMutableArray array];
    NSMutableData *symbols = [NSMutableData data];
    for (NSString *name in NoshiAccountNames()) {
        NSString *title = [NoshiAccountInfo(name) objectForKey:@"title"];
        [titles addObject:title.length ? title : NSLocalizedString(@"account.title", nil)];
        [names addObject:name];
        NoshiSymbol symbol = [name isEqualToString:active] ? NoshiSymbolCheck : NoshiSymbolPerson;
        [symbols appendBytes:&symbol length:sizeof(symbol)];
    }
    [titles addObject:NSLocalizedString(@"account.add", nil)];
    NoshiSymbol plus = NoshiSymbolPlusCircle;
    [symbols appendBytes:&plus length:sizeof(plus)];
    NSUInteger accounts = names.count;
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:titles symbols:(const NoshiSymbol *)symbols.bytes handler:^(NSUInteger picked) {
        if (picked >= accounts) {
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiAccountAddNotification object:nil];
            return;
        }
        NSString *name = [names objectAtIndex:picked];
        if ([name isEqualToString:active]) return;
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiAccountSwitchNotification object:nil userInfo:[NSDictionary dictionaryWithObject:name forKey:@"name"]];
    }] autorelease];
    CGRect area = [tabBar convertRect:frame toView:self.view];
    menu.bottomInset = self.view.bounds.size.height - area.origin.y;
    [menu showInView:self.view anchor:CGPointMake(CGRectGetMaxX(area), area.origin.y - 8)];
}

@end

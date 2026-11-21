#import "noshi_alert_view.h"
#import "noshi_power_notice.h"
#import "noshi_app_delegate.h"
#import <objc/message.h>
#import "noshi_quick_actions.h"
#import "noshi_share_intake.h"
#import "noshi_window.h"
#import "noshi_crash_log.h"
#import "noshi_app_icon.h"
#import "noshi_now_playing.h"

#import "noshi_accounts.h"
#import "noshi_avatar_cache.h"
#import "noshi_session_profile.h"
#import "noshi_call_controller.h"
#import "noshi_group_call_presenter.h"
#import "noshi_language.h"
#import "noshi_link_router.h"
#import "noshi_lite_mode.h"
#import "noshi_music_player.h"
#import "noshi_notifier.h"
#import "noshi_night_mode.h"
#import "noshi_session_namecolor.h"
#import "noshi_session_notifysettings.h"
#import "noshi_perf_probe.h"
#import "noshi_wallpaper.h"
#import "noshi_traffic_store.h"
#import "noshi_chat_settings.h"
#import "noshi_back_swipe.h"
#import "noshi_passcode_lock.h"
#import "noshi_release_check.h"
#import "noshi_problem_report.h"
#import "noshi_proxy_settings.h"
#import "noshi_session_data.h"
#import "noshi_platform.h"
#import "noshi_shiro.h"
#import "noshi_shiro_failure_prompt.h"
#import "noshi_traffic_store.h"
#import "noshi_splash_view.h"
#import "noshi_split_controller.h"
#import "noshi_theme.h"
#import "noshi_imported_theme.h"
#import "noshi_alert.h"
#import "noshi_imported_theme_preview_controller.h"

#import <QuartzCore/QuartzCore.h>

@interface NoshiAppDelegate () {
    UIWindow *_window;
    UINavigationController *_navigation;
    NoshiCountryBook *_countries;
    NoshiSession *_session;
    NoshiLoginFlow *_login;
    NoshiNotifier *_notifier;
    NoshiPasscodeLock *_passcodeLock;
    NoshiBackSwipe *_backSwipe;
    NoshiSplashView *_splash;
    NoshiCallController *_callScreen;
    NoshiGroupCallPresenter *_groupPresenter;
    /* the call screen folded away while the call goes on, and the bar over the chats that brings it back */
    BOOL _callMinimized;
    BOOL _callMinimizing;
    UIButton *_callBar;
    NoshiCall *_callBarSnapshot;
    NSTimer *_callBarTimer;
    /* the newest snapshot of a call that began while the screen of the one before it was still leaving */
    NoshiCall *_pendingCall;
    NoshiAvatarCache *_callAvatars;
    NoshiMediaCache *_callMedia;
    NoshiShiro *_shiro;
    NoshiShiroRoute _shiroRoute;
    /* a link that arrived before anyone was signed in, opened once the main screen exists */
    NSString *_pendingLink;
    /* the account that has the connection now; the first one is named "" */
    NSString *_activeAccount;
    NSTimer *_ghostTimer;
    /* an account being added: its own session while the login runs, the name of its directory, and the screen the person returns to by going back */
    NoshiSession *_addSession;
    NSString *_addName;
    UIViewController *_addAnchor;
}
@end

@implementation NoshiAppDelegate

@synthesize window = _window;

/* a signed in start waits for the first list; a list that never reports must not hold the screen for ever */
#define SPLASH_LIMIT_SECONDS 5.0

/* keys and the database stay in the app's private support directory */
static NSString *NoshiSupportDirectory(void) {
    NSArray *roots = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *directory = [[roots objectAtIndex:0] stringByAppendingPathComponent:@"Noshigram"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"noshigram: cannot create %@: %@", directory, error);
    }
    return directory;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    /* before any text is asked for, so the first screen already speaks the chosen language */
    NoshiApplyInterfaceLanguage();
    NoshiLiteModeStart();
    NoshiTrafficStart();
    /* before the first screen reads the stored theme, so a start at night already wears the night theme */
    NoshiNightCheck(NO);
    /* and before the splash, the window and the tab bar, which draw with the colors of the tone that is current, light until it is applied */
    NoshiThemeApplyStored();
    NSString *directory = NoshiSupportDirectory();
    _activeAccount = [NoshiAccountActive() copy];
    NSString *accountDirectory = NoshiAccountDirectory(_activeAccount);
    BOOL signedIn = [NoshiSession hasAccountInDirectory:accountDirectory];
    _session = [[NoshiSession alloc] initWithDirectory:accountDirectory];
    _session.delegate = self;
    _session.callDelegate = self;
    _groupPresenter = [[NoshiGroupCallPresenter alloc] initWithTopController:^UIViewController *{ return _navigation; } host:^UIView *{ return _navigation.view; }];
    _session.groupCallDelegate = _groupPresenter;
    /* the tunnel is wanted before the first connection, so a start with the VPN on never sends anything in the clear */
    _shiro = [[NoshiShiro alloc] initWithDirectory:directory];
    _session.shiro = _shiro;
    NoshiShiroSetActive(_shiro);
    _shiroRoute = _shiro.route;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shiroChanged:)
                                                 name:NoshiShiroStateDidChangeNotification object:_shiro];
    [_shiro resume];
    [_session start];
    _notifier = [[NoshiNotifier alloc] initWithSession:_session];
    if (signedIn) [_notifier start];
    else NoshiQuickActionsUpdate(nil);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountSwitchRequested:) name:NoshiAccountSwitchNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(proxyChanged:) name:NoshiProxyDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountAddRequested:) name:NoshiAccountAddNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChangedForLaunchImages) name:NoshiThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notifySettingsChanged:)
                                                 name:NoshiNotifySettingsDidChangeNotification object:nil];

    /* a shake is a thing the app answers (the pictures of a theme fall), so the system's offer to undo typing on a shake is turned off */
    application.applicationSupportsShakeToEdit = NO;
    self.window = [[[NoshiWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    self.window.backgroundColor = NoshiColorBackdrop();
    /* every screen draws its own bar, so the system one stays hidden and only its push animation is used */
    _navigation = [[UINavigationController alloc] initWithRootViewController:signedIn ? [self makeMainController] : [self makeWelcomeController]];
    _navigation.navigationBarHidden = YES;
    self.window.rootViewController = _navigation;
    _backSwipe = [[NoshiBackSwipe alloc] initWithNavigationController:_navigation];
    [self.window makeKeyAndVisible];
    _passcodeLock = [[NoshiPasscodeLock alloc] init];
    [_passcodeLock lockAtLaunch];
    [self showSplashSignedIn:signedIn];
    NoshiAppIconRestore();
    NoshiCrashLogStart();
    NoshiCrashLogWatchMemory();
    NoshiWallpaperWarm();
    NoshiPerfStart();
    NoshiNightStart(^BOOL{ return [self nightMayRebuildScreens]; });
    /* a tap on a notification that started the app: the chat opens once the screens exist */
    UILocalNotification *launching = [options objectForKey:UIApplicationLaunchOptionsLocalNotificationKey];
    if (launching && signedIn) dispatch_async(dispatch_get_main_queue(), ^{ [_notifier handleLocalNotification:launching]; });
    return YES;
}

/* copies the file of an "open in" into a folder of the app's own temporary directory, under its own name; nil when it cannot be read, which is logged with the reason */
static NSURL *NoshiKeepOpenedFile(NSURL *url, NSString **directory) {
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL scoped = NO;
    SEL start = NSSelectorFromString(@"startAccessingSecurityScopedResource");
    if ([url respondsToSelector:start]) scoped = ((BOOL (*)(id, SEL))objc_msgSend)(url, start);
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"noshigram-open-%08x%08x", arc4random(), arc4random()]];
    NSError *error = nil;
    NSString *name = [url lastPathComponent];
    NSString *target = [folder stringByAppendingPathComponent:name];
    BOOL kept = name.length && [manager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error] &&
                [manager copyItemAtPath:[url path] toPath:target error:&error];
    if (scoped) ((void (*)(id, SEL))objc_msgSend)(url, NSSelectorFromString(@"stopAccessingSecurityScopedResource"));
    if (!kept) {
        NSLog(@"noshigram: the opened file %@ could not be copied: %@", name, error);
        [manager removeItemAtPath:folder error:NULL];
        return nil;
    }
    *directory = folder;
    return [NSURL fileURLWithPath:target];
}

/* tg:// links, which the Info.plist hands to the app, and t.me links when something passes them on: they open
   inside the app */
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    (void)application;
    (void)sourceApplication;
    (void)annotation;
    if ([url isFileURL] && [[[url path] pathExtension] caseInsensitiveCompare:@"tgios-theme"] == NSOrderedSame) {
        [NoshiImportedThemePreviewController openURL:url fromController:_navigation];
        return YES;
    }
    /* a picture, a video or any file from the share sheet or "open in" waits in the inbox of the app until the person picks its chat */
    if ([url isFileURL]) {
        if (![NoshiSession hasAccountInDirectory:NoshiAccountDirectory(_activeAccount)]) return NO;
        /* the file is taken into the app now: a file opened in place from another app (ifile hands over the path of the file itself, a crash log of the system for one) is readable
           only while this call runs, and the chat is picked later, which made the send fail with SHARE_FILE_UNREADABLE. the copy is what is sent and what is removed afterwards */
        NSString *directory = nil;
        NSURL *kept = NoshiKeepOpenedFile(url, &directory);
        if (!kept) return NO;
        NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:kept], @"urls", directory, @"directory", nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:NoshiShareFilesNotification object:self userInfo:info];
        });
        return YES;
    }
    /* the share extension opens the app with this address after it left the files in the shared folder */
    if ([url.scheme isEqualToString:@"noshigram"] && [url.host isEqualToString:@"share"]) {
        if (![NoshiSession hasAccountInDirectory:NoshiAccountDirectory(_activeAccount)]) return NO;
        dispatch_async(dispatch_get_main_queue(), ^{ NoshiShareCollectPending(); });
        return YES;
    }
    if (!NoshiIsTelegramLink(url)) return NO;
    NSString *address = url.absoluteString;
    if (![NoshiSession hasAccountInDirectory:NoshiAccountDirectory(_activeAccount)]) {
        [_pendingLink release];
        _pendingLink = [address copy];
        return YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self openLink:address]; });
    return YES;
}

/* ios 9 may deliver a document through the options form instead of the older source-application form */
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary *)options {
    (void)options;
    return [self application:application openURL:url sourceApplication:nil annotation:nil];
}

- (void)openLink:(NSString *)address {
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiOpenLinkNotification object:self
                                                      userInfo:[NSDictionary dictionaryWithObject:address forKey:@"url"]];
}

/* the icon the person chose on the color of the screen under it, light or dark; the launch image of a jailbroken phone is drawn with the same icon and color (see
   NoshiAppIconRefreshLaunchImages), so the start is one splash and not a swap */
- (void)showSplashSignedIn:(BOOL)signedIn {
    /* before ios 8 a window subview does not rotate with the root controller */
    UIView *host = _navigation.view ? _navigation.view : self.window;
    _splash = [[NoshiSplashView alloc] initWithFrame:host.bounds color:NoshiColorScreen()];
    [host addSubview:_splash];
    if (signedIn) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dismissSplash)
                                                     name:NoshiFirstScreenReadyNotification object:nil];
        [self performSelector:@selector(dismissSplash) withObject:nil afterDelay:SPLASH_LIMIT_SECONDS];
    } else {
        /* the welcome screen has nothing to wait for, so the splash only covers its first frame */
        [self performSelector:@selector(dismissSplash) withObject:nil afterDelay:0];
    }
}

- (void)dismissSplash {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dismissSplash) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NoshiFirstScreenReadyNotification object:nil];
    [_splash dismiss];
    [_splash release];
    _splash = nil;
    NoshiReleaseCheckStart(self.window);
}

/* the links follow the route: a tunnel that came up or dropped moves them to the other path */
- (void)shiroChanged:(NSNotification *)note {
    (void)note;
    /* a tunnel that did not open says so on a card of its own, wherever the person is: the app sends nothing while the tunnel is wanted and down */
    if (_shiro.state == NoshiShiroStateFailed && _shiro.enabled) NoshiShowShiroFailure(_shiro);
    if (_shiro.route == _shiroRoute) return;
    _shiroRoute = _shiro.route;
    [_session routeChanged];
    /* the session of a login of another account dialed meanwhile too, and waits on the old path */
    [_addSession routeChanged];
}

- (void)proxyChanged:(NSNotification *)note {
    (void)note;
    [_session routeChanged];
    [_session reconnect];
    [_addSession routeChanged];
    [_addSession reconnect];
}

- (void)themeChangedForLaunchImages {
    NoshiAppIconRefreshLaunchImages();
}

- (void)notifySettingsChanged:(NSNotification *)note {
    (void)note;
    [_notifier settingsChanged];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    /* ios 6 resigns active for the notification center and the multitasking bar without going to the background, and a cover raised then hid both; the
       snapshot of the switcher is taken after this method returns, so the cover is raised here */
    [_passcodeLock cover];
    [_passcodeLock noteLeave];
    /* what was counted since the last tick is kept before the system may end the app */
    NoshiTrafficFlush();
    [_notifier applicationDidEnterBackground:application];
    /* the system suspends the process at once, wherever the session thread is */
    __block UIBackgroundTaskIdentifier hold = UIBackgroundTaskInvalid;
    void (^endHold)(void) = ^{
        if (hold == UIBackgroundTaskInvalid) return;
        [application endBackgroundTask:hold];
        hold = UIBackgroundTaskInvalid;
    };
    hold = [application beginBackgroundTaskWithExpirationHandler:endHold];
    [_session afterPendingWork:endHold];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [_passcodeLock evaluateReturn];
    [_notifier applicationDidBecomeActive:application];
    /* the remote events of a song that plays need a responder in the window, which a screen that came and went in the meantime may have taken the focus from */
    NoshiRemoteControlsClaim();
    /* what the share extension left while the app was away, when the wake address did not reach it */
    if ([NoshiSession hasAccountInDirectory:NoshiAccountDirectory(_activeAccount)]) NoshiShareCollectPending();
    NoshiPowerNoticeStart();
}

/* the system's wake for a look, every so often on ios 7 and later: the notifier reads the chat list and posts what is new */
/* UIBackgroundFetchResult is an NSUInteger, which the sdk of the armv7 slice does not name and the arm64 one does */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-parameter-types"
- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(NSUInteger result))completionHandler {
    (void)application;
    [_notifier performFetchWithCompletion:completionHandler];
}
#pragma clang diagnostic pop

/* a chat chosen from the menu of the icon (3d touch, ios 9 and later); the item is an id since the sdk of the armv7 slice has no such class */
- (void)application:(UIApplication *)application performActionForShortcutItem:(id)shortcutItem completionHandler:(void (^)(BOOL succeeded))completionHandler {
    (void)application;
    NSDictionary *info = NoshiQuickActionChatInfo(shortcutItem);
    BOOL signedIn = [NoshiSession hasAccountInDirectory:NoshiAccountDirectory(_activeAccount)];
    if (info && signedIn) [_notifier openChatWithInfo:info];
    completionHandler(info && signedIn);
}

/* a tap on a notification while the app runs */
- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification {
    /* one that arrives while the app is on screen is not a tap, and must not pull the person into another chat */
    if (application.applicationState == UIApplicationStateActive) return;
    [_notifier handleLocalNotification:notification];
}

/* the headset and lock screen buttons of systems before ios 7.1, where they come as events to the responder chain, which ends here */
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.type != UIEventTypeRemoteControl) return;
    NoshiMusicPlayer *player = [NoshiMusicPlayer sharedPlayer];
    switch (event.subtype) {
    case UIEventSubtypeRemoteControlPlay:
        if (player.state == NoshiMusicStatePaused) [player togglePause];
        break;
    case UIEventSubtypeRemoteControlPause:
        [player pause];
        break;
    case UIEventSubtypeRemoteControlTogglePlayPause:
        [player togglePause];
        break;
    case UIEventSubtypeRemoteControlNextTrack:
        [player next];
        break;
    case UIEventSubtypeRemoteControlPreviousTrack:
        [player previous];
        break;
    default:
        break;
    }
}

/* a switch of the theme builds the main screens again, and what is pushed over them would keep the old colors, so
   the automatic night theme waits for the person to be on the list itself */
- (BOOL)nightMayRebuildScreens {
    if (_navigation.viewControllers.count != 1 || self.window.rootViewController.presentedViewController) return NO;
    UIViewController *top = _navigation.topViewController;
    if ([top isKindOfClass:[NoshiSplitController class]]) return [(NoshiSplitController *)top canRebuildForTheme];
    return [top isKindOfClass:[NoshiMainController class]];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
    /* the link gave up while the app slept, so the first sight of it again tries once more */
    [_session reconnect];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_ghostTimer invalidate];
    [_callBarTimer invalidate];
    [_callBarTimer release];
    [_callBarSnapshot release];
    [_callBar release];
    [_activeAccount release];
    [_addName release];
    [_addSession release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_splash release];
    NoshiNightStop();
    [_notifier stop];
    [_backSwipe release];
    [_passcodeLock release];
    [_notifier release];
    [_session stop];
    _session.delegate = nil;
    _session.callDelegate = nil;
    _session.groupCallDelegate = nil;
    _session.shiro = nil;
    NoshiShiroSetActive(nil);
    [_shiro release];
    [_callScreen release];
    [_groupPresenter release];
    [_pendingCall release];
    [_callAvatars release];
    [_callMedia release];
    [_window release];
    [_navigation release];
    [_countries release];
    [_session release];
    [_login release];
    [super dealloc];
}

#pragma mark screens

/* the screens before the login are light only */
- (UIViewController *)makeWelcomeController {
    /* the welcome screen and the login after it wear the style the person chose, light until they choose */
    NoshiThemeApplyStored();
    /* the classic bars are dark, but the login of that style has none, so its status bar follows the color of the screen */
    UIApplication *application = [UIApplication sharedApplication];
    if ([application respondsToSelector:@selector(setStatusBarStyle:animated:)]) {
        [application setStatusBarStyle:NoshiStatusBarStyle(NoshiThemeIsDark()) animated:NO];
    }
    NoshiWelcomeController *welcome = [[[NoshiWelcomeController alloc] init] autorelease];
    welcome.delegate = self;
    welcome.shiro = _shiro;
    return welcome;
}

/* ghost mode keeps the account offline: the server counts a connection in use as online, so the status is sent again every half minute */
- (void)ghostTick {
    if (!NoshiChatFlagGet(NoshiChatFlagGhostOffline) || ![NoshiSession hasAccountInDirectory:NoshiAccountDirectory(_activeAccount)]) return;
    [_session sendOfflineStatus];
}

- (UIViewController *)makeMainController {
    NoshiThemeApplyStored();
    if (!_ghostTimer) _ghostTimer = [[NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(ghostTick) userInfo:nil repeats:YES] retain];
    /* the question about the crash of the last run comes a little after the screens are up; the link has time to come while the person reads it */
    NoshiSession *reporting = [_session retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (reporting == _session) NoshiProblemReportsStart(reporting);
        [reporting release];
    });
    NoshiMainController *main = [[[NoshiMainController alloc] initWithSession:_session] autorelease];
    main.delegate = self;
    /* the colors the server lists for names above the seven built in are kept for the chats to draw with; a failure leaves the ones kept before */
    [_session loadNameColors:^(NSArray *colors, NSString *errorName) {
        (void)colors;
        if (errorName) NSLog(@"noshigram: the name colors did not load: %@", errorName);
    }];
    /* the list of accounts shows this one by name while another is connected */
    NSString *account = [[_activeAccount copy] autorelease];
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        if (!items.count) {
            NSLog(@"noshigram: the account record was not refreshed: %@", errorName);
            return;
        }
        NoshiPerson *person = [items objectAtIndex:0];
        NoshiAccountSetInfo(account, person.name, person.username, person.userId);
    }];
    /* what the account holds for notifications is copied to the phone, which the banners and the settings read */
    [_session syncNotifySettingsWithCompletion:^(NSString *errorName) {
        if (errorName) NSLog(@"noshigram: the notification settings did not sync: %@", errorName);
    }];
    /* a tablet has room for the lists and what they open side by side */
    if (NoshiIsPad()) return [[[NoshiSplitController alloc] initWithMain:main] autorelease];
    return main;
}

/* both ways in need the country book, which the phone screen of either path uses */
- (BOOL)prepareLogin {
    return [self prepareLoginWithSession:_session];
}

- (BOOL)prepareLoginWithSession:(NoshiSession *)session {
    if (!_countries) _countries = [[NoshiCountryBook alloc] init];
    if (!_countries) {
        [self showNoticeTitle:NSLocalizedString(@"notice.countries.title", nil)
                      message:NSLocalizedString(@"notice.countries.message", nil)];
        return NO;
    }
    [_login release];
    _login = [[NoshiLoginFlow alloc] initWithNavigation:_navigation session:session countryBook:_countries];
    _login.delegate = self;
    return YES;
}

- (void)welcomeControllerDidTapStart:(NoshiWelcomeController *)controller {
    (void)controller;
    if ([self prepareLogin]) [_login begin];
}

- (void)welcomeControllerDidRequestQr:(NoshiWelcomeController *)controller {
    (void)controller;
    if ([self prepareLogin]) [_login beginWithQr];
}

- (void)loginFlow:(NoshiLoginFlow *)flow didAuthorizeUser:(long long)userId {
    [flow retain];
    NoshiSession *retired = nil;
    if (_addSession) {
        /* the same person signed in twice would have two directories for one account */
        if (NoshiAccountNameOfUser(userId, _addName)) {
            UIViewController *anchor = _addAnchor ? _addAnchor : [_navigation.viewControllers objectAtIndex:0];
            [self showNoticeTitle:nil message:NSLocalizedString(@"account.add.same", nil)];
            /* the server made a session for this login already; dropping the key here would leave it in the list of devices, so the session logs itself out first and
               its directory goes once that is done */
            NoshiSession *duplicate = _addSession;
            NSString *duplicateName = _addName;
            _addSession = nil;
            _addName = nil;
            [self cancelAddAccount];
            [_navigation popToViewController:anchor animated:YES];
            duplicate.delegate = nil;
            duplicate.shiro = nil;
            [duplicate signOut:^(NSString *errorName) {
                if (errorName) NSLog(@"noshigram: the duplicate login was not ended on the server: %@", errorName);
                [duplicate stop];
                NoshiAccountRemove(duplicateName);
                [duplicate release];
                [duplicateName release];
            }];
            [flow release];
            return;
        }
        [_notifier stop];
        [_notifier release];
        retired = _session;
        _session = _addSession;
        _addSession = nil;
        _navigation.delegate = nil;
        _addAnchor = nil;
        [_activeAccount release];
        _activeAccount = _addName;
        _addName = nil;
        NoshiAccountSetActive(_activeAccount);
        [self bindSession:_session];
        _notifier = [[NoshiNotifier alloc] initWithSession:_session];
    }
    [_navigation setViewControllers:[NSArray arrayWithObject:[self makeMainController]] animated:YES];
    /* the flow gave up the session delegate when it finished; the app takes it back for later events */
    _session.delegate = self;
    [_notifier start];
    [_login release];
    _login = nil;
    [flow release];
    if (retired) {
        [self retireSession:retired];
        [retired release];
    }
    if (_pendingLink) {
        NSString *address = [_pendingLink autorelease];
        _pendingLink = nil;
        dispatch_async(dispatch_get_main_queue(), ^{ [self openLink:address]; });
    }
}

#pragma mark main screen

- (void)mainController:(NoshiMainController *)controller requestsSignOut:(void (^)(NSString *errorName))completion {
    (void)controller;
    [_session signOut:completion];
}

/* only events after the login reach here: a dropped session sends the user back to the welcome screen */
- (void)session:(NoshiSession *)session didReceiveAuthEvent:(NoshiAuthEvent *)event {
    (void)session;
    if (event.kind != NoshiAuthEventLoggedOut) return;
    NSLog(@"noshigram: account '%@' lost its key on the server, the app moves to the first account that is left and forgets this one", _activeAccount);
    [_notifier stop];
    [_login release];
    _login = nil;
    /* another account signed in takes over; the last one leaves the welcome screen */
    NSString *gone = [[_activeAccount copy] autorelease];
    NSArray *left = NoshiAccountNames();
    [self activateAccount:left.count ? [left objectAtIndex:0] : @""];
    NoshiAccountRemove(gone);
}

#pragma mark accounts

- (void)bindSession:(NoshiSession *)session {
    session.delegate = self;
    session.callDelegate = self;
    session.groupCallDelegate = _groupPresenter;
    session.shiro = _shiro;
}

/* the connection of an account that is no longer the active one is closed, so only one account is online */
- (void)retireSession:(NoshiSession *)session {
    session.delegate = nil;
    session.callDelegate = nil;
    session.groupCallDelegate = nil;
    session.shiro = nil;
    [session stop];
}

/* makes the account the one with the connection, and shows its chats, or the welcome screen for one that is not signed in */
- (void)activateAccount:(NSString *)name {
    if (_callScreen || _groupPresenter.callIsShown || _addSession) {
        NSLog(@"noshigram: the switch to account '%@' waits for the call or the added account to end (call %d, group call %d, adding %d)", name,
              _callScreen != nil, _groupPresenter.callIsShown, _addSession != nil);
        return;
    }
    UIViewController *shown = _navigation.presentedViewController;
    if (shown) [_navigation dismissViewControllerAnimated:NO completion:nil];
    [_notifier stop];
    [_notifier release];
    /* the connection of the account that leaves is closed before the next one opens, so two clients of one process are never live together and the key files of the two
       directories are never touched at once */
    NoshiSession *retired = _session;
    _session = nil;
    [self retireSession:retired];
    [retired release];
    [_activeAccount release];
    _activeAccount = [name copy];
    NoshiAccountSetActive(name);
    _session = [[NoshiSession alloc] initWithDirectory:NoshiAccountDirectory(name)];
    [self bindSession:_session];
    [_session start];
    _notifier = [[NoshiNotifier alloc] initWithSession:_session];
    BOOL signedIn = [NoshiSession hasAccountInDirectory:NoshiAccountDirectory(name)];
    UIViewController *root;
    if (signedIn) {
        [_notifier start];
        root = [self makeMainController];
    } else {
        root = [self makeWelcomeController];
    }
    [_navigation setViewControllers:[NSArray arrayWithObject:root] animated:YES];
}

- (void)accountSwitchRequested:(NSNotification *)note {
    NSString *name = [note.userInfo objectForKey:@"name"];
    if (!name || [name isEqualToString:_activeAccount]) {
        NSLog(@"noshigram: the switch to account '%@' is ignored, it is the active one ('%@')", name, _activeAccount);
        return;
    }
    if (![NoshiSession hasAccountInDirectory:NoshiAccountDirectory(name)]) {
        NSLog(@"noshigram: the switch to account '%@' is ignored, its directory holds no signed in account", name);
        return;
    }
    [self activateAccount:name];
}

/* the phone screen is pushed over the screens the person is on, with a session of its own in a new directory; going back from it gives the directory up */
- (void)accountAddRequested:(NSNotification *)note {
    (void)note;
    if (_addSession || _callScreen) return;
    NSString *name = NoshiAccountMakeNew();
    if (!name) {
        [self showNoticeTitle:nil message:NSLocalizedString(@"account.add.failed", nil)];
        return;
    }
    _addName = [name copy];
    _addSession = [[NoshiSession alloc] initWithDirectory:NoshiAccountDirectory(name)];
    _addSession.shiro = _shiro;
    [_addSession start];
    if (![self prepareLoginWithSession:_addSession]) {
        [self cancelAddAccount];
        return;
    }
    _addAnchor = _navigation.topViewController;
    _navigation.delegate = self;
    [_login begin];
}

- (void)cancelAddAccount {
    _navigation.delegate = nil;
    _addAnchor = nil;
    [_login release];
    _login = nil;
    if (_addSession) {
        _addSession.shiro = nil;
        [_addSession stop];
        [_addSession release];
        _addSession = nil;
    }
    if (_addName) NoshiAccountRemove(_addName);
    [_addName release];
    _addName = nil;
}

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    (void)navigationController;
    (void)animated;
    if (_addSession && viewController == _addAnchor) [self cancelAddAccount];
}

/* a call that begins or rings gets the full screen over whatever is open; later snapshots only update it */
- (void)session:(NoshiSession *)session callDidChange:(NoshiCall *)call {
    if (_callScreen && _callScreen.finishing && call.callId != _callScreen.callId) {
        [_pendingCall release];
        _pendingCall = [call retain];
        return;
    }
    if (!_callScreen && call.phase == NoshiCallPhaseEnded && call.end == NoshiCallEndNone) return;
    if (call != _callBarSnapshot) {
        [_callBarSnapshot release];
        _callBarSnapshot = [call retain];
    }
    if (!_callScreen) {
        if (!_callAvatars) {
            NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
            NSString *directory = [[caches stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"avatars"];
            _callAvatars = [[NoshiAvatarCache alloc] initWithSession:session directory:directory];
            _callMedia = [[NoshiMediaCache alloc] initWithSession:session directory:[[caches stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"media"]];
        }
        _callScreen = [[NoshiCallController alloc] initWithSession:session];
        _callScreen.avatars = _callAvatars;
        _callScreen.media = _callMedia;
        _callScreen.photo = call.photo;
        /* not retained by the block: the screen holds the block */
        __block NoshiCallController *shown = _callScreen;
        _callScreen.onMinimize = ^{ [self minimizeCall]; };
        _callScreen.onFinish = ^{
            if (_callScreen != shown) return;
            [self hideCallBar];
            _callMinimizing = NO;
            [_callBarSnapshot release];
            _callBarSnapshot = nil;
            [_callScreen release];
            _callScreen = nil;
            NoshiCall *next = [[_pendingCall retain] autorelease];
            [_pendingCall release];
            _pendingCall = nil;
            if (next) [self session:_session callDidChange:next];
        };
        UIViewController *top = _navigation;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:_callScreen animated:YES completion:nil];
    }
    if (_callMinimized) {
        if (call.phase == NoshiCallPhaseEnded) [self hideCallBar];
        else [self refreshCallBarWithCall:call];
    }
    [_callScreen updateWithCall:call];
}

#pragma mark minimized call

- (void)minimizeCall {
    if (!_callScreen || _callMinimized || _callScreen.finishing) return;
    _callMinimized = YES;
    _callMinimizing = YES;
    NoshiCallController *screen = _callScreen;
    /* the bar is there from the start: it stands under the screen that is sliding away, and a dismissal whose completion never comes (a screen that was not presented any more)
       used to leave the call with no way back */
    [self showCallBar];
    [screen dismissViewControllerAnimated:YES completion:^{
        if (_callScreen != screen) return;
        _callMinimizing = NO;
        if (_callMinimized) [self showCallBar];
    }];
}

- (void)restoreCallAnimated:(BOOL)animated {
    if (!_callScreen || !_callMinimized) return;
    /* a dismissal still sliding is waited for; one that is over (the screen is no longer presented) is not, whatever its completion did */
    if (_callMinimizing && _callScreen.presentingViewController) return;
    _callMinimizing = NO;
    _callMinimized = NO;
    [self hideCallBar];
    UIViewController *top = _navigation;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:_callScreen animated:animated completion:nil];
}

- (void)callBarTapped {
    [self restoreCallAnimated:YES];
}

- (void)showCallBar {
    if (!_callBar) {
        _callBar = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _callBar.backgroundColor = [UIColor colorWithRed:0.18f green:0.72f blue:0.35f alpha:1];
        _callBar.layer.cornerRadius = 16;
        _callBar.titleLabel.font = NoshiFontSemibold(13);
        _callBar.titleLabel.lineBreakMode = UILineBreakModeTailTruncation;
        _callBar.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [_callBar addTarget:self action:@selector(callBarTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    [self refreshCallBarWithCall:_callBarSnapshot];
    if (!_callBarTimer) _callBarTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(callBarTick:) userInfo:nil repeats:YES] retain];
    UIView *host = _navigation.view;
    CGFloat width = MIN(MAX(0, host.bounds.size.width - 104), 240);
    _callBar.frame = CGRectMake(floor((host.bounds.size.width - width) / 2), NoshiStatusBarHeight() + 4, width, 32);
    [host addSubview:_callBar];
}

- (void)refreshCallBarWithCall:(NoshiCall *)call {
    NSString *name = call.peerName.length ? call.peerName : @"";
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"call.return", nil), name];
    if (call.phase == NoshiCallPhaseActive && call.startedAt > 0) {
        NSInteger seconds = MAX(0, (NSInteger)([NSDate timeIntervalSinceReferenceDate] - call.startedAt));
        NSString *time = seconds >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(seconds / 3600), (long)(seconds / 60 % 60), (long)(seconds % 60)]
                                         : [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
        title = [NSString stringWithFormat:@"%@ · %@", name, time];
    } else if (call.phase == NoshiCallPhaseReconnecting) {
        title = NSLocalizedString(@"call.reconnecting", nil);
    }
    [_callBar setTitle:title forState:UIControlStateNormal];
    _callBar.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"call.return", nil), name];
}

- (void)callBarTick:(NSTimer *)timer {
    (void)timer;
    [self refreshCallBarWithCall:_callBarSnapshot];
    /* a screen that was pushed or put back under it must not cover the way back into the call */
    UIView *host = _navigation.view;
    if (_callBar.superview != host) [host addSubview:_callBar];
    else [host bringSubviewToFront:_callBar];
}

- (void)hideCallBar {
    _callMinimized = NO;
    [_callBarTimer invalidate];
    [_callBarTimer release];
    _callBarTimer = nil;
    [_callBar removeFromSuperview];
}

- (void)showNoticeTitle:(NSString *)title message:(NSString *)message {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:title message:message delegate:nil
                               cancelButtonTitle:NSLocalizedString(@"notice.ok", nil) otherButtonTitles:nil];
    [alert show];
    [alert release];
}

@end

#import "noshi_notifier.h"

#import <objc/message.h>

#import "noshi_background_keeper.h"
#import "noshi_chat_list.h"
#import "noshi_app_sounds.h"
#import "noshi_inapp_banner.h"
#import "noshi_lite_mode.h"
#import "noshi_notify_store.h"
#import "noshi_plural.h"
#import "noshi_quick_actions.h"
#import "noshi_session_internal.h"
#import "noshi_session_notify.h"
#import "noshi_voip_socket.h"
#import "noshi_weak_reference.h"

NSString *const NoshiOpenChatNotification = @"NoshiOpenChat";
NSString *const NoshiNotifySettingsDidChangeNotification = @"NoshiNotifySettingsDidChange";

#define KEY_ENABLED @"noshigram.notify.enabled"
static NSString *const NoshiNotifyAskedKey = @"noshigram.notify.asked";
#define KEY_SAVING @"noshigram.notify.saving"
/* a change of the store is looked at after this pause, so a burst of messages is one look */
#define DEBOUNCE_SECONDS 0.4
/* the system wakes a keep-alive app this often at best */
#define KEEP_ALIVE_SECONDS 600.0
/* on screen the chat list is read at most this often for the notices of other chats, since every look is a request */
#define FOREGROUND_LOOK_SECONDS 6.0
/* the chat list is read at most this often from the background, so a chat that writes all day is not a request for
   each message */
#define BACKGROUND_LOOK_SECONDS 3.0
#define FLOOD_WAIT_DEFAULT_SECONDS 30.0
#define FLOOD_WAIT_MAX_SECONDS 900.0
/* a quiet link in the background pings this rarely, since every ping wakes the radio; the disconnect delay sent with it follows the interval */
#define BACKGROUND_PING_MS 60000u
#define BACKGROUND_PING_SAVER_MS 120000u

static int32_t NoshiOpenChatKind;
static long long NoshiOpenChatPeer;

void NoshiNotifierSetOpenChat(int32_t peerKind, long long peerId) {
    NoshiOpenChatKind = peerKind;
    NoshiOpenChatPeer = peerId;
}

static BOOL NoshiNotifyFlag(NSString *key, BOOL fallback) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return stored ? [stored boolValue] : fallback;
}

static void NoshiNotifySetFlag(NSString *key, BOOL on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiNotifySettingsDidChangeNotification object:nil];
}

BOOL NoshiNotifyEnabled(void) { return NoshiNotifyFlag(KEY_ENABLED, YES); }
void NoshiNotifySetEnabled(BOOL on) { NoshiNotifySetFlag(KEY_ENABLED, on); }
/* the silence keeps the app awake where no voip socket can: ios 7 and later, and ios 5 and 6 while the link runs through the tunnel, whose streams are not sockets of the network */
static BOOL NoshiKeeperNeeded(NoshiSession *session) { (void)session; return [NoshiBackgroundKeeper needed]; }
BOOL NoshiNotifySavingAvailable(NoshiSession *session) { return NoshiKeeperNeeded(session); }
BOOL NoshiNotifySaving(void) { return NoshiNotifyFlag(KEY_SAVING, NO); }
void NoshiNotifySetSaving(BOOL on) { NoshiNotifySetFlag(KEY_SAVING, on); }

BOOL NoshiBackgroundLinkWanted(void) {
    return NoshiNotifyEnabled() && NoshiVoipSocketSupported();
}

/* the answer of the delegate of ios 10 and later: the system tells it about a tap on a notification, and asks
   whether to show one while the app is on screen */
@interface NoshiUserNotificationDelegate : NSObject {
    NoshiWeakReference *_notifier;
}
- (id)initWithNotifier:(NoshiWeakReference *)notifier;
@end

@interface NoshiNotifier () {
    NoshiBackgroundKeeper *_keeper;
    id _unDelegate;
    void (^_fetchHandler)(NSUInteger result);
    NoshiSession *_session;
    NoshiAvatarCache *_bannerAvatars;
    NoshiWeakReference *_weak;
    NSTimer *_debounce;
    BOOL _scanning;
    BOOL _rescan;
    /* a look for the badge alone was asked for while another one was on its way: that one was counted before what the person read since, so its answer is not the badge */
    BOOL _rescanForBadge;
    BOOL _started;
    NSUInteger _scanGeneration;
    NSTimeInterval _lastForegroundLook;
    NSTimeInterval _lastBackgroundLook;
    /* the server asked for quiet until this time (reference date), zero when it did not */
    NSTimeInterval _blockedUntil;
    /* held from the moment a change woke the app until the look it caused is done, so the system does not put it back to sleep */
    UIBackgroundTaskIdentifier _wakeTask;
}
@end

@implementation NoshiNotifier

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _wakeTask = UIBackgroundTaskInvalid;
    _keeper = [[NoshiBackgroundKeeper alloc] init];
    /* it has to be in place before the app finishes launching, or the tap that started it is lost */
    id center = [self userNotificationCenter];
    if (center) {
        _unDelegate = [[NoshiUserNotificationDelegate alloc] initWithNotifier:_weak];
        [center setValue:_unDelegate forKey:@"delegate"];
    }
    return self;
}

- (void)dealloc {
    [[self userNotificationCenter] setValue:nil forKey:@"delegate"];
    [_unDelegate release];
    [_keeper stop];
    [_keeper release];
    [_fetchHandler release];
    [_weak clear];
    [_weak release];
    [_debounce invalidate];
    [_bannerAvatars release];
    [_session release];
    [super dealloc];
}

#pragma mark system calls that the sdks of the two slices do not agree on

/* setKeepAliveTimeout:handler: is deprecated from ios 9 and its header is gone from the newest sdk, so it is called by name */
- (void)installKeepAliveForApplication:(UIApplication *)application {
    SEL install = NSSelectorFromString(@"setKeepAliveTimeout:handler:");
    if (!NoshiVoipSocketSupported() || ![application respondsToSelector:install]) return;
    NoshiWeakReference *weak = _weak;
    void (^handler)(void) = ^{
        /* the handler may come on any thread */
        dispatch_async(dispatch_get_main_queue(), ^{ [(NoshiNotifier *)weak.target keepAliveWake]; });
    };
    BOOL installed = ((BOOL (*)(id, SEL, NSTimeInterval, void (^)(void)))objc_msgSend)(application, install, KEEP_ALIVE_SECONDS, handler);
    NSLog(@"noshigram: keep-alive %@", installed ? @"installed" : @"refused");
}

- (void)clearKeepAliveForApplication:(UIApplication *)application {
    SEL clear = NSSelectorFromString(@"clearKeepAliveTimeout");
    if ([application respondsToSelector:clear]) ((void (*)(id, SEL))objc_msgSend)(application, clear);
}

/* the notification center of ios 10 and later, nil before; every call to it goes by name, since the sdk of the armv7 slice does not have it */
static id user_notification_center(void) {
    Class center = NSClassFromString(@"UNUserNotificationCenter");
    return center ? [center performSelector:NSSelectorFromString(@"currentNotificationCenter")] : nil;
}

- (id)userNotificationCenter {
    return user_notification_center();
}

/* ios 8 asks before a local notification may show or the badge may change, and ios 10 moved the question to the notification center; the
   classes are looked up by name for the older sdk */
- (void)registerForNotificationsInApplication:(UIApplication *)application askAgain:(BOOL)askAgain {
    id center = [self userNotificationCenter];
    /* the system puts the question only while the choice is open, but a build that it takes for a new app opens the choice again, and the question came at every launch;
       it is put once, and the switch of the notifications in the settings puts it again. The wake interval below is not kept by the system and is set at every launch */
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL ask = askAgain || ![defaults boolForKey:NoshiNotifyAskedKey];
    if (ask) [defaults setBool:YES forKey:NoshiNotifyAskedKey];
    if (center) {
        /* badge, sound and alert are bits 0, 1 and 2 of UNAuthorizationOptions */
        void (^answered)(BOOL, NSError *) = ^(BOOL granted, NSError *error) {
            if (error) NSLog(@"noshigram: the notification permission could not be asked: %@", error);
            else if (!granted) NSLog(@"noshigram: the notifications are not allowed in the settings of the system");
        };
        if (ask) ((void (*)(id, SEL, NSUInteger, void (^)(BOOL, NSError *)))objc_msgSend)(center, NSSelectorFromString(@"requestAuthorizationWithOptions:completionHandler:"), 1 | 2 | 4, answered);
        /* a sleeping app is woken by the system now and then to look; the system picks the interval */
        SEL interval = NSSelectorFromString(@"setMinimumBackgroundFetchInterval:");
        if ([application respondsToSelector:interval]) ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(application, interval, 0);
        return;
    }
    if (!ask) return;
    SEL register_ = NSSelectorFromString(@"registerUserNotificationSettings:");
    Class settingsClass = NSClassFromString(@"UIUserNotificationSettings");
    if (!settingsClass || ![application respondsToSelector:register_]) return;
    /* alert, badge and sound are bits 4, 1 and 2 of UIUserNotificationType */
    NSUInteger types = 4 | 1 | 2;
    SEL make = NSSelectorFromString(@"settingsForTypes:categories:");
    id settings = ((id (*)(id, SEL, NSUInteger, id))objc_msgSend)(settingsClass, make, types, nil);
    if (settings) ((void (*)(id, SEL, id))objc_msgSend)(application, register_, settings);
}

/* every notification of ours that is waiting or on the screen of the person goes, and the badge with them */
- (void)clearNotificationsInApplication:(UIApplication *)application {
    id center = [self userNotificationCenter];
    if (center) {
        ((void (*)(id, SEL))objc_msgSend)(center, NSSelectorFromString(@"removeAllPendingNotificationRequests"));
        ((void (*)(id, SEL))objc_msgSend)(center, NSSelectorFromString(@"removeAllDeliveredNotifications"));
    }
    [application cancelAllLocalNotifications];
    application.applicationIconBadgeNumber = 0;
}

#pragma mark lifecycle

- (void)start {
    if (_started) return;
    _started = YES;
    NoshiWeakReference *weak = _weak;
    [_session post:^{
        [_session setChangeHook:^{
            dispatch_async(dispatch_get_main_queue(), ^{ [(NoshiNotifier *)weak.target storeChanged]; });
        }];
    }];
    if (NoshiNotifyEnabled()) [self registerForNotificationsInApplication:[UIApplication sharedApplication] askAgain:NO];
}

- (void)stop {
    /* the menu of the icon names chats of the account that leaves, and it outlives the process */
    NoshiQuickActionsUpdate(nil);
    if (!_started) return;
    _started = NO;
    ++_scanGeneration;
    _scanning = NO;
    _rescan = NO;
    _rescanForBadge = NO;
    [_session post:^{ [_session setChangeHook:nil]; }];
    [_debounce invalidate];
    _debounce = nil;
    [self endWakeTask];
    UIApplication *application = [UIApplication sharedApplication];
    [self clearNotificationsInApplication:application];
    [self clearKeepAliveForApplication:application];
    [_keeper stop];
}

- (void)settingsChanged {
    UIApplication *application = [UIApplication sharedApplication];
    if (NoshiNotifyEnabled()) {
        [self registerForNotificationsInApplication:application askAgain:YES];
        return;
    }
    ++_scanGeneration;
    _scanning = NO;
    _rescan = NO;
    _rescanForBadge = NO;
    [_debounce invalidate];
    _debounce = nil;
    [self endWakeTask];
    [self clearNotificationsInApplication:application];
    [self clearKeepAliveForApplication:application];
    [_keeper stop];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    if (!_started || !NoshiNotifyEnabled()) return;
    [_session setPingInterval:NoshiLitePowerSaverApplied() ? BACKGROUND_PING_SAVER_MS : BACKGROUND_PING_MS];
    /* what is unread now is old news: the first look after leaving the screen takes it as the baseline and sets the badge */
    [self scanAnnouncing:NO application:application];
    [self installKeepAliveForApplication:application];
    /* where no VoIP socket is kept for the app, playing silence is what keeps it, and its link, awake */
    if (NoshiKeeperNeeded(_session) && !NoshiNotifySaving()) [_keeper start];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    /* the person is here: the reminder and the banners still in the notification center are old news. ios 5 and 6 empty the notification center only when the badge goes to zero, so it is
       set back at once; left at zero it would stay empty until a scan on the way to the background got an answer, and a scan blocked by a flood wait or a dead link never does */
    NSInteger badge = application.applicationIconBadgeNumber;
    [self clearNotificationsInApplication:application];
    application.applicationIconBadgeNumber = badge;
    [_session setPingInterval:0];
    [_debounce invalidate];
    _debounce = nil;
    [self clearKeepAliveForApplication:application];
    [_keeper stop];
}

- (void)handleLocalNotification:(UILocalNotification *)notification {
    [self openChatWithInfo:notification.userInfo];
}

/* the numbers a notification carries name its chat; the main screen opens it */
- (void)openChatWithInfo:(NSDictionary *)info {
    NSNumber *kind = [info objectForKey:@"kind"], *peer = [info objectForKey:@"peer"];
    if (![kind isKindOfClass:[NSNumber class]] || ![peer isKindOfClass:[NSNumber class]]) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiOpenChatNotification object:self
                                                      userInfo:[NSDictionary dictionaryWithObjectsAndKeys:kind, @"kind", peer, @"peer", nil]];
}

#pragma mark looking

- (void)storeChanged {
    if (!_started || !NoshiNotifyEnabled() || _debounce) return;
    UIApplication *application = [UIApplication sharedApplication];
    if (application.applicationState == UIApplicationStateActive) {
        /* on screen, the app tells of other chats itself: a sound, a shake, a card; with all three off there is nothing to look for */
        if (!NoshiNotifyInAppSounds() && !NoshiNotifyInAppVibrate() && !NoshiNotifyInAppPreview()) return;
        NSTimeInterval wait = FOREGROUND_LOOK_SECONDS - ([NSDate timeIntervalSinceReferenceDate] - _lastForegroundLook);
        _debounce = [NSTimer scheduledTimerWithTimeInterval:MAX(DEBOUNCE_SECONDS, wait) target:self selector:@selector(debounceFired:) userInfo:nil repeats:NO];
        return;
    }
    if (_wakeTask == UIBackgroundTaskInvalid) {
        NoshiWeakReference *weak = _weak;
        _wakeTask = [application beginBackgroundTaskWithExpirationHandler:^{ [(NoshiNotifier *)weak.target endWakeTask]; }];
    }
    NSTimeInterval since = [NSDate timeIntervalSinceReferenceDate] - _lastBackgroundLook;
    _debounce = [NSTimer scheduledTimerWithTimeInterval:MAX(DEBOUNCE_SECONDS, BACKGROUND_LOOK_SECONDS - since) target:self selector:@selector(debounceFired:) userInfo:nil repeats:NO];
}

- (void)endWakeTask {
    if (_wakeTask == UIBackgroundTaskInvalid) return;
    UIBackgroundTaskIdentifier task = _wakeTask;
    _wakeTask = UIBackgroundTaskInvalid;
    [[UIApplication sharedApplication] endBackgroundTask:task];
}

- (void)debounceFired:(NSTimer *)timer {
    (void)timer;
    _debounce = nil;
    UIApplication *application = [UIApplication sharedApplication];
    if (application.applicationState == UIApplicationStateActive) _lastForegroundLook = [NSDate timeIntervalSinceReferenceDate];
    [self scanAnnouncing:YES application:application];
}

/* every ten minutes the system wakes the app; a background task keeps the app awake until the answer is in */
- (void)keepAliveWake {
    if (!_started || !NoshiNotifyEnabled()) return;
    UIApplication *application = [UIApplication sharedApplication];
    if (application.applicationState == UIApplicationStateActive) return;
    [_session reconnect];
    [self scanAnnouncing:YES application:application];
}

/* the system woke the app for a look: the link is made sure of, the chat list is read and the news are posted */
- (void)performFetchWithCompletion:(void (^)(NSUInteger result))completion {
    if (!_started || !NoshiNotifyEnabled()) {
        completion(1);
        return;
    }
    if (_fetchHandler) {
        /* a second wake while one is still looking has nothing to add */
        completion(1);
        return;
    }
    _fetchHandler = [completion copy];
    NoshiWeakReference *weak = _weak;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [(NoshiNotifier *)weak.target finishFetch:2];
    });
    UIApplication *application = [UIApplication sharedApplication];
    [_session reconnect];
    [self scanAnnouncing:YES application:application];
}

/* result is the system's UIBackgroundFetchResult */
- (void)finishFetch:(NSUInteger)result {
    if (!_fetchHandler) return;
    void (^handler)(NSUInteger) = _fetchHandler;
    _fetchHandler = nil;
    handler(result);
    [handler release];
}

/* the icon badge from the list the screen holds, for the moment the server cannot be asked: a flood wait on the chat list (a scan of folders pages through it) used to leave
   the number of an earlier look on the icon after everything was read, and a timer cannot run for the length of the wait once the app is suspended */
- (void)applyLocalBadgeInApplication:(UIApplication *)application {
    NSArray *dialogs = NoshiMainDialogsSnapshot();
    if (!dialogs) return;
    NSInteger badge = 0;
    BOOL includeMuted = NoshiNotifyBadgeMuted(), messages = NoshiNotifyBadgeMessages();
    for (NoshiDialog *dialog in dialogs) {
        if (dialog.folder || dialog.saved || dialog.unreadCount <= 0 || (dialog.peerKind == 3 && dialog.left)) continue;
        if (dialog.muted && !includeMuted) continue;
        badge += messages ? dialog.unreadCount : 1;
    }
    application.applicationIconBadgeNumber = NoshiNotifyBadgeShown() ? badge : 0;
}

- (void)scanAnnouncing:(BOOL)announce application:(UIApplication *)application {
    if (!_started || !NoshiNotifyEnabled()) return;
    if (_scanning) {
        _rescan = _rescan || announce;
        if (!announce) _rescanForBadge = YES;
        return;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now < _blockedUntil) {
        [self applyLocalBadgeInApplication:application];
        /* one look when the wait is over, whatever came in meanwhile */
        if (!_debounce) _debounce = [NSTimer scheduledTimerWithTimeInterval:_blockedUntil - now + 0.5 target:self selector:@selector(debounceFired:) userInfo:nil repeats:NO];
        [self finishFetch:1];
        return;
    }
    if (application.applicationState != UIApplicationStateActive) _lastBackgroundLook = now;
    _scanning = YES;
    NSUInteger generation = ++_scanGeneration;
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    task = [application beginBackgroundTaskWithExpirationHandler:^{
        UIBackgroundTaskIdentifier expired = task;
        task = UIBackgroundTaskInvalid;
        if (expired != UIBackgroundTaskInvalid) [application endBackgroundTask:expired];
    }];
    NoshiWeakReference *weak = _weak;
    NoshiNotifyScanOptions options;
    memset(&options, 0, sizeof(options));
    NoshiNotifyRulesSnapshot(&options.rules);
    options.badgeShown = NoshiNotifyBadgeShown();
    options.badgeMuted = NoshiNotifyBadgeMuted();
    options.badgeMessages = NoshiNotifyBadgeMessages();
    /* the chat screen clears its chat only when it disappears, not when the app goes to the home screen, and a chat nobody looks at must still announce */
    BOOL onScreen = application.applicationState == UIApplicationStateActive;
    options.activeKind = onScreen ? NoshiOpenChatKind : 0;
    options.activePeer = onScreen ? NoshiOpenChatPeer : 0;
    [_session scanNotificationsAnnouncing:announce options:options completion:^(NSArray *events, NSUInteger more, NSString *moreText, NSInteger badge, NSInteger unreadChats, NSString *errorName) {
        NoshiNotifier *notifier = weak.target;
        if (notifier && notifier->_scanGeneration == generation) {
            notifier->_scanning = NO;
            if (errorName) {
                NSLog(@"noshigram: notification look failed: %@", errorName);
                if ([errorName hasPrefix:@"FLOOD_WAIT"]) {
                    /* the link is fine, the list was asked for too often: nothing is reconnected, and the next look waits what the server said */
                    NSRange colon = [errorName rangeOfString:@":"];
                    NSTimeInterval seconds = colon.location == NSNotFound ? FLOOD_WAIT_DEFAULT_SECONDS : [[errorName substringFromIndex:colon.location + 1] doubleValue];
                    if (seconds < 1) seconds = FLOOD_WAIT_DEFAULT_SECONDS;
                    notifier->_blockedUntil = [NSDate timeIntervalSinceReferenceDate] + MIN(seconds, FLOOD_WAIT_MAX_SECONDS);
                    [notifier applyLocalBadgeInApplication:application];
                    notifier->_rescan = YES;
                } else if (![errorName isEqualToString:@"NO_ACCOUNT"]) {
                    /* a look that cannot be made says the link is down; one try to bring it back */
                    [notifier->_session reconnect];
                }
                [notifier finishFetch:2];
            } else {
                [notifier postEvents:events more:more moreText:moreText badge:badge unreadChats:unreadChats application:application];
                [notifier finishFetch:events.count ? 0 : 1];
            }
            if (notifier->_rescan) {
                notifier->_rescan = NO;
                notifier->_rescanForBadge = NO;
                [notifier scanAnnouncing:YES application:application];
            } else if (notifier->_rescanForBadge) {
                notifier->_rescanForBadge = NO;
                [notifier scanAnnouncing:NO application:application];
            } else {
                [notifier endWakeTask];
            }
        }
        if (task != UIBackgroundTaskInvalid) {
            UIBackgroundTaskIdentifier finished = task;
            task = UIBackgroundTaskInvalid;
            [application endBackgroundTask:finished];
        }
    }];
}

#pragma mark posting

/* ios 10 and later: a notification content with its title and body, posted at once; its identifier is the
   message's, so the same news twice is one notification, and the chat is its thread */
/* the file of the bundle a banner plays: nil for a banner without a sound, the empty string for the default one */
static NSString *NoshiBannerSoundFile(const noshi_notify_sound *sound) {
    if (sound->kind == NOSHI_SOUND_NONE) return nil;
    if (sound->kind == NOSHI_SOUND_LOCAL && sound->data[0]) {
        NSString *name = [NSString stringWithUTF8String:sound->data];
        if (name.length && [[NSBundle mainBundle] pathForResource:name ofType:nil]) return name;
    }
    return @"";
}

static void present_with_center(id center, NSString *title, NSString *body, NSDictionary *info, NSString *sound) {
    Class contentClass = NSClassFromString(@"UNMutableNotificationContent");
    Class soundClass = NSClassFromString(@"UNNotificationSound");
    Class requestClass = NSClassFromString(@"UNNotificationRequest");
    if (!contentClass || !soundClass || !requestClass) return;
    id content = [[[contentClass alloc] init] autorelease];
    [content setValue:title forKey:@"title"];
    [content setValue:body forKey:@"body"];
    if (sound) {
        id tone = sound.length ? [soundClass performSelector:NSSelectorFromString(@"soundNamed:") withObject:sound]
                               : [soundClass performSelector:NSSelectorFromString(@"defaultSound")];
        [content setValue:tone forKey:@"sound"];
    }
    if (info) [content setValue:info forKey:@"userInfo"];
    NSNumber *kind = [info objectForKey:@"kind"], *peer = [info objectForKey:@"peer"], *mid = [info objectForKey:@"mid"];
    NSString *identifier = [[info objectForKey:@"identifier"] isKindOfClass:[NSString class]] ? [info objectForKey:@"identifier"] : @"noshigram.more";
    if (kind && peer) {
        identifier = [NSString stringWithFormat:@"noshigram.%@.%@.%@", kind, peer, mid ? mid : @0];
        [content setValue:[NSString stringWithFormat:@"%@.%@", kind, peer] forKey:@"threadIdentifier"];
    }
    id request = ((id (*)(id, SEL, NSString *, id, id))objc_msgSend)(requestClass, NSSelectorFromString(@"requestWithIdentifier:content:trigger:"),
                                                                    identifier, content, nil);
    void (^added)(NSError *) = ^(NSError *error) {
        if (error) NSLog(@"noshigram: a notification was not posted: %@", error);
    };
    ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(center, NSSelectorFromString(@"addNotificationRequest:withCompletionHandler:"), request, added);
}

static void present_notice(NSString *title, NSString *body, NSDictionary *info, NSString *sound, UIApplication *application) {
    id center = user_notification_center();
    if (center) {
        present_with_center(center, title, body, info, sound);
        return;
    }
    UILocalNotification *notification = [[[UILocalNotification alloc] init] autorelease];
    /* the title is its own line only from ios 8.2; before that it leads the text */
    if ([notification respondsToSelector:NSSelectorFromString(@"setAlertTitle:")]) {
        [notification setValue:title forKey:@"alertTitle"];
        notification.alertBody = body;
    } else {
        notification.alertBody = title.length ? [NSString stringWithFormat:@"%@: %@", title, body] : body;
    }
    if (sound) notification.soundName = sound.length ? sound : UILocalNotificationDefaultSoundName;
    notification.userInfo = info;
    [application presentLocalNotificationNow:notification];
}

- (void)present:(NSString *)title body:(NSString *)body userInfo:(NSDictionary *)info sound:(NSString *)sound application:(UIApplication *)application {
    present_notice(title, body, info, sound, application);
}

/* the reminder of what is still unread, a notification that fires after the interval of the settings and is taken
   back whenever the app looks again; an hour by default */
- (void)scheduleRepeatForUnread:(NSInteger)unreadChats application:(UIApplication *)application {
    for (UILocalNotification *old in [[application.scheduledLocalNotifications copy] autorelease]) {
        if ([[old.userInfo objectForKey:@"repeat"] boolValue]) [application cancelLocalNotification:old];
    }
    NSInteger minutes = NoshiNotifyRepeatMinutes();
    if (unreadChats <= 0 || minutes <= 0 || !NoshiNotifyEnabled()) return;
    UILocalNotification *reminder = [[[UILocalNotification alloc] init] autorelease];
    reminder.fireDate = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)minutes * 60];
    reminder.alertBody = [NSString stringWithFormat:NSLocalizedString([@"notif.repeat.body." stringByAppendingString:NoshiPluralForm(unreadChats)], nil), (int)unreadChats];
    reminder.soundName = UILocalNotificationDefaultSoundName;
    reminder.userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"repeat"];
    [application scheduleLocalNotification:reminder];
}

/* the pictures on the cards come from the same folder as the lists' ones, so a face the lists loaded is already on disk */
- (NoshiAvatarCache *)bannerAvatars {
    if (!_bannerAvatars) {
        NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *directory = [[caches stringByAppendingPathComponent:@"Noshigram"] stringByAppendingPathComponent:@"avatars"];
        _bannerAvatars = [[NoshiAvatarCache alloc] initWithSession:_session directory:directory];
    }
    return _bannerAvatars;
}

/* the app is on screen: a message of another chat is a sound, a shake and a card, as the in-app settings say; the card names the chat and, with the preview on,
   shows the text */
- (void)announceInApp:(NSArray *)events {
    NoshiNotifyEvent *event = events.lastObject;
    if (!event) return;
    noshi_notify_sound tone = event.sound;
    if (NoshiNotifyInAppSounds() && tone.kind != NOSHI_SOUND_NONE) {
        NSString *file = NoshiBannerSoundFile(&tone);
        NoshiPlayAppSound(file.length ? file : @"sound_in.caf");
    }
    if (NoshiNotifyChatVibrates(event.peerKind, event.peerId)) NoshiVibrateOnce();
    if (!NoshiNotifyInAppPreview()) return;
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:event.peerKind], @"kind", [NSNumber numberWithLongLong:event.peerId], @"peer", nil];
    [NoshiInAppBanner showTitle:event.title body:event.body dialog:event.dialog avatars:[self bannerAvatars] tap:^{ [self openChatWithInfo:info]; }];
}

- (void)postEvents:(NSArray *)events more:(NSUInteger)more moreText:(NSString *)moreText badge:(NSInteger)badge unreadChats:(NSInteger)unreadChats application:(UIApplication *)application {
    /* nothing is posted while the app is on screen: the look may have finished after the person came back */
    if (application.applicationState != UIApplicationStateActive) {
        for (NoshiNotifyEvent *event in events) {
            NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:event.peerKind], @"kind",
                                  [NSNumber numberWithLongLong:event.peerId], @"peer", [NSNumber numberWithInt:event.messageId], @"mid", nil];
            noshi_notify_sound tone = event.sound;
            [self present:event.title body:event.body userInfo:info sound:NoshiBannerSoundFile(&tone) application:application];
        }
        if (more && moreText) [self present:@"" body:moreText userInfo:nil sound:@"" application:application];
        application.applicationIconBadgeNumber = badge;
        [self scheduleRepeatForUnread:unreadChats application:application];
        return;
    }
    /* the badge is the account's count of unread chats whether the app is on screen or not, so what the person read here is on the icon when the app is left */
    application.applicationIconBadgeNumber = badge;
    [self announceInApp:events];
}

@end

@implementation NoshiUserNotificationDelegate

- (id)initWithNotifier:(NoshiWeakReference *)notifier {
    self = [super init];
    if (!self) return nil;
    _notifier = [notifier retain];
    return self;
}

- (void)dealloc {
    [_notifier release];
    [super dealloc];
}

/* the app shows its own news while it is on screen, so nothing from the system is shown over it */
- (void)userNotificationCenter:(id)center willPresentNotification:(id)notification withCompletionHandler:(void (^)(NSUInteger options))handler {
    (void)center;
    (void)notification;
    handler(0);
}

- (void)userNotificationCenter:(id)center didReceiveNotificationResponse:(id)response withCompletionHandler:(void (^)(void))handler {
    (void)center;
    NSDictionary *info = [response valueForKeyPath:@"notification.request.content.userInfo"];
    void (^done)(void) = [handler copy];
    /* the chat opens once the screens exist, which for a tap that started the app is a turn of the run loop later */
    dispatch_async(dispatch_get_main_queue(), ^{
        [(NoshiNotifier *)_notifier.target openChatWithInfo:info];
        done();
        [done release];
    });
}

@end

#import "noshi_notifications_settings_controller.h"

#import "noshi_alert.h"
#import "noshi_notifications_kind_controller.h"
#import "noshi_notifier.h"
#import "noshi_notify_store.h"
#import "noshi_sheet.h"
#import "noshi_weak_reference.h"

@interface NoshiNotificationsSettingsController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NSArray *_exceptions;
    BOOL _resetting;
}
@end

@implementation NoshiNotificationsSettingsController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.notifications", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rebuild) object:nil];
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_exceptions release];
    [super dealloc];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scheduleRebuild) name:NoshiNotifyStoreDidChangeNotification object:nil];
    [self rebuild];
    [_session syncNotifySettingsWithCompletion:^(NSString *errorName) {
        if (errorName) NSLog(@"noshigram: the notification settings did not sync: %@", errorName);
    }];
}

/* a sync writes the store once for every part of the settings it brings, and each write is a full redraw of the table; the changes of one turn of the run loop
   are drawn once */
- (void)scheduleRebuild {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(rebuild) object:nil];
    [self performSelector:@selector(rebuild) withObject:nil afterDelay:0];
}

/* the page shows only how many exceptions each kind has, so a list with the same counts changes nothing on it */
static NSString *NoshiExceptionCounts(NSArray *exceptions) {
    NSMutableString *counts = [NSMutableString string];
    for (NoshiNotifyKind kind = NoshiNotifyKindPrivate; kind <= NoshiNotifyKindStories; ++kind) {
        [counts appendFormat:@"%lu,", (unsigned long)NoshiNotifyExceptionsForKind(exceptions, kind).count];
    }
    return counts;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NoshiWeakReference *weak = _weak;
    [_session loadNotifyExceptionsWithCompletion:^(NSArray *exceptions, NSString *errorName) {
        NoshiNotificationsSettingsController *me = weak.target;
        if (!me) return;
        if (!exceptions) {
            NSLog(@"noshigram: the notification exceptions did not load: %@", errorName);
            return;
        }
        BOOL same = me->_exceptions && [NoshiExceptionCounts(me->_exceptions) isEqualToString:NoshiExceptionCounts(exceptions)];
        [me->_exceptions release];
        me->_exceptions = [exceptions retain];
        if (!same) [me rebuild];
    }];
}

#pragma mark kinds

static NSString *NoshiReactionsLine(const noshi_reaction_notify *r) {
    NSMutableArray *parts = [NSMutableArray array];
    if (r->messages_from != NOSHI_REACTION_FROM_NOBODY) [parts addObject:NSLocalizedString(@"notif.reactions.messages", nil)];
    if (r->stories_from != NOSHI_REACTION_FROM_NOBODY) [parts addObject:NSLocalizedString(@"notif.reactions.stories", nil)];
    return parts.count ? [parts componentsJoinedByString:@", "] : NSLocalizedString(@"notif.off", nil);
}

- (NSString *)lineForKind:(NoshiNotifyKind)kind {
    int32_t now = NoshiNotifyNow();
    if (kind == NoshiNotifyKindReactions) {
        noshi_reaction_notify r = NoshiNotifyReactionsStored();
        return NoshiReactionsLine(&r);
    }
    NSArray *list = NoshiNotifyExceptionsForKind(_exceptions, kind);
    NSString *state;
    if (kind == NoshiNotifyKindStories) {
        noshi_peer_notify s = NoshiNotifyScopeStored(NOSHI_SCOPE_USERS);
        state = NSLocalizedString(s.has_stories_muted && !s.stories_muted ? @"notif.on" : @"notif.off", nil);
    } else {
        noshi_peer_notify s = NoshiNotifyScopeStored(NoshiNotifyScopeOfKind(kind));
        state = NoshiNotifyMuteText(s.has_mute ? s.mute_until : 0);
        (void)now;
    }
    if (!list.count) return NSLocalizedString(@"notif.tap", nil);
    return [NSString stringWithFormat:@"%@, %@", state, NoshiNotifyCountText(@"notif.exceptions", list.count)];
}

- (BOOL)kindEnabled:(NoshiNotifyKind)kind {
    if (kind == NoshiNotifyKindReactions) {
        noshi_reaction_notify r = NoshiNotifyReactionsStored();
        return r.messages_from != NOSHI_REACTION_FROM_NOBODY || r.stories_from != NOSHI_REACTION_FROM_NOBODY;
    }
    if (kind == NoshiNotifyKindStories) {
        noshi_peer_notify s = NoshiNotifyScopeStored(NOSHI_SCOPE_USERS);
        return s.has_stories_muted && !s.stories_muted;
    }
    noshi_peer_notify s = NoshiNotifyScopeStored(NoshiNotifyScopeOfKind(kind));
    return noshi_notify_mute_state(s.has_mute ? s.mute_until : 0, NoshiNotifyNow()) == 0;
}

- (void)report:(NSString *)errorName {
    if (!errorName) return;
    NSLog(@"noshigram: the notification settings were not kept: %@", errorName);
    NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
    [_session syncNotifySettingsWithCompletion:nil];
}

/* the switch of a kind on the main list: on or off at once; the exceptions are told of first tells of them */
- (void)setKind:(NoshiNotifyKind)kind enabled:(BOOL)on {
    NoshiWeakReference *weak = _weak;
    void (^apply)(void) = ^{
        NoshiNotificationsSettingsController *me = weak.target;
        if (!me) return;
        if (kind == NoshiNotifyKindReactions) {
            noshi_reaction_notify r = NoshiNotifyReactionsStored();
            r.messages_from = r.stories_from = on ? NOSHI_REACTION_FROM_EVERYONE : NOSHI_REACTION_FROM_NOBODY;
            NoshiNotifyReactionsStore(&r);
            [me->_session sendReactionNotifyWithCompletion:^(NSString *errorName) { [(NoshiNotificationsSettingsController *)weak.target report:errorName]; }];
            return;
        }
        noshi_notify_scope scope = NoshiNotifyScopeOfKind(kind);
        noshi_peer_notify s = NoshiNotifyScopeStored(scope);
        if (kind == NoshiNotifyKindStories) {
            /* off goes back to the stories of the people the person talks to most */
            s.has_stories_muted = on ? 1 : 0;
            s.stories_muted = 0;
        } else {
            s.has_mute = 1;
            s.mute_until = on ? 0 : NOSHI_NOTIFY_MUTE_FOREVER;
        }
        NoshiNotifyScopeStore(scope, &s);
        [me->_session sendNotifyScope:scope completion:^(NSString *errorName) { [(NoshiNotificationsSettingsController *)weak.target report:errorName]; }];
    };
    NSArray *list = kind == NoshiNotifyKindReactions ? nil : NoshiNotifyExceptionsForKind(_exceptions, kind);
    if (!list.count) {
        apply();
        return;
    }
    NSString *about = NoshiNotifyCountText(kind == NoshiNotifyKindPrivate || kind == NoshiNotifyKindStories ? @"notif.exceptions" : @"notif.chats", list.count);
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"notif.exceptions.alert", nil), about];
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.exceptions.view", nil), @"OK", nil];
    NoshiSettingsChoose(self, message, options, ^(NSUInteger index) {
        NoshiNotificationsSettingsController *me = weak.target;
        if (!me) return;
        if (index == 0) [me openKind:kind];
        else apply();
    });
    /* a cancelled sheet leaves the switch where the person put it, so the rows are drawn again from what is stored */
    [self rebuild];
}

- (void)openKind:(NoshiNotifyKind)kind {
    NoshiNotificationsKindController *page = [[[NoshiNotificationsKindController alloc] initWithSession:_session avatars:_avatars media:_media kind:kind
                                                                                                  exceptions:_exceptions] autorelease];
    [self.navigationController pushViewController:page animated:YES];
}

- (NoshiSettingsRow *)rowForKind:(NoshiNotifyKind)kind symbol:(NoshiSymbol)symbol tone:(NoshiSettingsTone)tone title:(NSString *)title {
    NoshiWeakReference *weak = _weak;
    NoshiSettingsRow *row = [NoshiSettingsRow switchRowWithSymbol:symbol tone:tone title:title subtitle:[self lineForKind:kind] on:[self kindEnabled:kind]
                                                               toggle:^(BOOL on) { [(NoshiNotificationsSettingsController *)weak.target setKind:kind enabled:on]; }];
    row.tap = ^{ [(NoshiNotificationsSettingsController *)weak.target openKind:kind]; };
    return row;
}

#pragma mark rows

static NoshiSettingsRow *NoshiFlagRow(NSString *key, BOOL on, void (^set)(BOOL)) {
    return [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(key, nil) subtitle:nil on:on toggle:set];
}

- (NSString *)repeatText {
    NSInteger minutes = NoshiNotifyRepeatMinutes();
    if (minutes == 0) return NSLocalizedString(@"notif.repeat.never", nil);
    if (minutes < 60) return [NSString stringWithFormat:NSLocalizedString(@"notif.repeat.minutes", nil), (int)minutes];
    return [NSString stringWithFormat:NSLocalizedString(@"notif.repeat.hours", nil), (int)(minutes / 60)];
}

- (void)chooseRepeat {
    static const NSInteger values[] = {0, 5, 10, 30, 60, 120, 240};
    NSMutableArray *options = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
        NSInteger m = values[i];
        [options addObject:m == 0 ? NSLocalizedString(@"notif.repeat.never", nil)
                                  : (m < 60 ? [NSString stringWithFormat:NSLocalizedString(@"notif.repeat.minutes", nil), (int)m]
                                            : [NSString stringWithFormat:NSLocalizedString(@"notif.repeat.hours", nil), (int)(m / 60)])];
    }
    NoshiSettingsChoose(self, NSLocalizedString(@"notif.repeat", nil), options, ^(NSUInteger index) { NoshiNotifySetRepeatMinutes(values[index]); });
}

- (void)chooseCallVibration {
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.vibrate.default", nil), NSLocalizedString(@"notif.vibrate.off", nil), nil];
    NoshiSettingsChoose(self, NSLocalizedString(@"notif.vibrate", nil), options, ^(NSUInteger index) { NoshiNotifySetCallVibration(index == 0 ? 0 : 2); });
}

- (void)confirmReset {
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"notif.reset.alert", nil), NSLocalizedString(@"notif.reset.confirm", nil), ^{
        NoshiNotificationsSettingsController *me = weak.target;
        if (!me || me->_resetting) return;
        me->_resetting = YES;
        [me->_session resetAllNotifySettingsWithCompletion:^(NSString *errorName) {
            NoshiNotificationsSettingsController *again = weak.target;
            if (!again) return;
            again->_resetting = NO;
            if (errorName) {
                NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
                return;
            }
            [again->_exceptions release];
            again->_exceptions = nil;
            NoshiShowNotice(nil, NSLocalizedString(@"notif.reset.done", nil));
            [again rebuild];
        }];
    });
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    NSArray *kinds = [NSArray arrayWithObjects:
        [self rowForKind:NoshiNotifyKindPrivate symbol:NoshiSymbolPerson tone:NoshiSettingsToneBlue title:NSLocalizedString(@"notif.private", nil)],
        [self rowForKind:NoshiNotifyKindGroups symbol:NoshiSymbolGroupsMenu tone:NoshiSettingsToneGreen title:NSLocalizedString(@"notif.groups", nil)],
        [self rowForKind:NoshiNotifyKindChannels symbol:NoshiSymbolMegaphone tone:NoshiSettingsToneOrange title:NSLocalizedString(@"notif.channels", nil)],
        [self rowForKind:NoshiNotifyKindStories symbol:NoshiSymbolGallery tone:NoshiSettingsTonePurple title:NSLocalizedString(@"notif.stories", nil)],
        [self rowForKind:NoshiNotifyKindReactions symbol:NoshiSymbolHeart tone:NoshiSettingsToneRed title:NSLocalizedString(@"notif.reactions", nil)], nil];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"notif.chats.header", nil) footer:nil rows:kinds]];

    NoshiSettingsRow *vibrate = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"notif.vibrate", nil)
                                                             value:NSLocalizedString(NoshiNotifyCallVibration() == 0 ? @"notif.vibrate.default" : @"notif.vibrate.off", nil)
                                                               tap:^{ [(NoshiNotificationsSettingsController *)weak.target chooseCallVibration]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"notif.calls.header", nil) footer:nil rows:[NSArray arrayWithObject:vibrate]]];

    NSArray *badge = [NSArray arrayWithObjects:
        NoshiFlagRow(@"notif.badge.show", NoshiNotifyBadgeShown(), ^(BOOL on) { NoshiNotifySetBadgeShown(on); }),
        NoshiFlagRow(@"notif.badge.muted", NoshiNotifyBadgeMuted(), ^(BOOL on) { NoshiNotifySetBadgeMuted(on); }),
        NoshiFlagRow(@"notif.badge.messages", NoshiNotifyBadgeMessages(), ^(BOOL on) { NoshiNotifySetBadgeMessages(on); }), nil];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"notif.badge.header", nil) footer:nil rows:badge]];

    NSArray *inApp = [NSArray arrayWithObjects:
        NoshiFlagRow(@"notif.inapp.sounds", NoshiNotifyInAppSounds(), ^(BOOL on) { NoshiNotifySetInAppSounds(on); }),
        NoshiFlagRow(@"notif.inapp.vibrate", NoshiNotifyInAppVibrate(), ^(BOOL on) { NoshiNotifySetInAppVibrate(on); }),
        NoshiFlagRow(@"notif.inapp.preview", NoshiNotifyInAppPreview(), ^(BOOL on) { NoshiNotifySetInAppPreview(on); }),
        NoshiFlagRow(@"notif.inchat", NoshiNotifyInChatSounds(), ^(BOOL on) { NoshiNotifySetInChatSounds(on); }), nil];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"notif.inapp.header", nil) footer:nil rows:inApp]];

    NoshiSettingsRow *joined = NoshiFlagRow(@"notif.contactjoined", NoshiNotifyContactJoined(), ^(BOOL on) {
        NoshiNotificationsSettingsController *me = weak.target;
        if (!me) return;
        BOOL before = !on;
        NoshiNotifySetContactJoined(on);
        [me->_session setContactJoinedNotify:on completion:^(NSString *errorName) {
            if (!errorName) return;
            NoshiNotifySetContactJoined(before);
            [(NoshiNotificationsSettingsController *)weak.target report:errorName];
        }];
    });
    NSArray *events = [NSArray arrayWithObjects:joined, NoshiFlagRow(@"notif.pinned", NoshiNotifyPinnedMessages(), ^(BOOL on) { NoshiNotifySetPinnedMessages(on); }), nil];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"notif.events.header", nil) footer:nil rows:events]];

    NSMutableArray *other = [NSMutableArray array];
    [other addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.master", nil) subtitle:NSLocalizedString(@"notif.master.info", nil) on:NoshiNotifyEnabled()
                                                     toggle:^(BOOL on) { NoshiNotifySetEnabled(on); }]];
    if (NoshiNotifySavingAvailable(_session)) {
        [other addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"settings.notify.saving", nil) subtitle:NSLocalizedString(@"settings.notify.saving.subtitle", nil)
                                                             on:NoshiNotifySaving() toggle:^(BOOL on) { NoshiNotifySetSaving(on); }]];
    }
    /* the line about banners and the economy mode stands right under the two rows it is about, and the repeat has a card of its own */
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"notif.other.header", nil) footer:NSLocalizedString(@"settings.notify.footer", nil) rows:other]];
    NoshiSettingsRow *repeat = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"notif.repeat", nil) value:[self repeatText]
                                                              tap:^{ [(NoshiNotificationsSettingsController *)weak.target chooseRepeat]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:repeat]]];

    NoshiSettingsRow *reset = [NoshiSettingsRow rowWithSymbol:NoshiSymbolBroom tone:NoshiSettingsToneRed title:NSLocalizedString(@"notif.reset", nil)
                                                         subtitle:NSLocalizedString(@"notif.reset.info", nil) value:nil
                                                              tap:^{ [(NoshiNotificationsSettingsController *)weak.target confirmReset]; }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:reset]]];
    self.sections = sections;
}

@end

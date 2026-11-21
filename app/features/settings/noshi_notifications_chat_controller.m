#import "noshi_notifications_chat_controller.h"

#import "noshi_alert.h"
#import "noshi_notifications_sound_controller.h"
#import "noshi_notify_store.h"
#import "noshi_sheet.h"
#import "noshi_weak_reference.h"

@interface NoshiNotificationsChatController () {
    NoshiSession *_session;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    int32_t _peerKind;
    long long _peerId;
    long long _peerHash;
    BOOL _broadcast;
    int32_t _topic;
    noshi_peer_notify _settings;
    BOOL _loaded;
    BOOL _sending;
}
@end

@implementation NoshiNotificationsChatController

- (id)initWithSession:(NoshiSession *)session media:(NoshiMediaCache *)media peerKind:(int32_t)peerKind peerId:(long long)peerId peerHash:(long long)peerHash
              channel:(BOOL)broadcast topic:(int32_t)topic title:(NSString *)title {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _peerKind = peerKind;
    _peerId = peerId;
    _peerHash = peerHash;
    _broadcast = broadcast;
    _topic = topic;
    memset(&_settings, 0, sizeof(_settings));
    self.pageTitle = title.length ? title : NSLocalizedString(@"notif.chat.header", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_media release];
    [super dealloc];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    NoshiWeakReference *weak = _weak;
    [_session loadNotifyOfPeerKind:_peerKind id:_peerId hash:_peerHash topic:_topic completion:^(NSValue *boxed, NSString *errorName) {
        NoshiNotificationsChatController *me = weak.target;
        if (!me) return;
        if (!boxed) {
            NSLog(@"noshigram: the notification settings of the chat did not load: %@", errorName);
            return;
        }
        [boxed getValue:&me->_settings];
        me->_loaded = YES;
        [me rebuild];
    }];
}

- (noshi_notify_scope)scope {
    return noshi_notify_scope_of(_peerKind, _broadcast);
}

/* what the chat does now: its own setting over the one of its kind */
- (void)effective:(noshi_notify_decision *)decision {
    noshi_notify_rules rules;
    NoshiNotifyRulesSnapshot(&rules);
    noshi_notify_decide(&rules, [self scope], &_settings, NoshiNotifyNow(), decision);
}

- (int32_t)effectiveMute {
    noshi_peer_notify kind = NoshiNotifyScopeStored([self scope]);
    if (_settings.has_mute) return _settings.mute_until;
    return kind.has_mute ? kind.mute_until : 0;
}

- (BOOL)hasOwnSettings {
    return _settings.has_mute || _settings.has_previews || _settings.has_silent || _settings.has_sound || _settings.has_stories_muted;
}

/* the change is made on the copy and the whole copy is sent, since the server takes the settings of a chat as one thing */
- (void)edit:(void (^)(noshi_peer_notify *settings))change {
    noshi_peer_notify before = _settings;
    change(&_settings);
    NoshiWeakReference *weak = _weak;
    [_session updateNotify:[NSValue valueWithBytes:&_settings objCType:@encode(noshi_peer_notify)] ofPeerKind:_peerKind id:_peerId hash:_peerHash topic:_topic
                completion:^(NSString *errorName) {
        NoshiNotificationsChatController *me = weak.target;
        if (!me || !errorName) return;
        NSLog(@"noshigram: the notification settings of the chat were not kept: %@", errorName);
        me->_settings = before;
        [me rebuild];
        NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
    }];
    [self rebuild];
}

- (void)chooseMute {
    NoshiWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.mute.on", nil), NSLocalizedString(@"notif.mute.1h", nil), NSLocalizedString(@"notif.mute.8h", nil),
                        NSLocalizedString(@"notif.mute.2d", nil), NSLocalizedString(@"notif.mute.off", nil), nil];
    NoshiSettingsChoose(self, NSLocalizedString(@"notif.chat.mute", nil), options, ^(NSUInteger index) {
        int32_t now = NoshiNotifyNow();
        int32_t until = index == 0 ? 0 : (index == 1 ? now + 3600 : (index == 2 ? now + 8 * 3600 : (index == 3 ? now + 2 * 86400 : NOSHI_NOTIFY_MUTE_FOREVER)));
        [(NoshiNotificationsChatController *)weak.target edit:^(noshi_peer_notify *s) {
            s->has_mute = 1;
            s->mute_until = until;
        }];
    });
}

- (void)openSound {
    NoshiWeakReference *weak = _weak;
    NSValue *current = _settings.has_sound ? [NSValue valueWithBytes:&_settings.sound objCType:@encode(noshi_notify_sound)] : nil;
    NoshiNotificationsSoundController *page = [[[NoshiNotificationsSoundController alloc] initWithSession:_session media:_media title:NSLocalizedString(@"notif.sound", nil)
                                                                                                    current:current apply:^(noshi_notify_sound sound) {
        [(NoshiNotificationsChatController *)weak.target edit:^(noshi_peer_notify *s) {
            s->has_sound = 1;
            s->sound = sound;
        }];
    }] autorelease];
    [self.navigationController pushViewController:page animated:YES];
}

- (void)confirmReset {
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"notif.chat.reset.alert", nil), NSLocalizedString(@"notif.reset.confirm", nil), ^{
        NoshiNotificationsChatController *me = weak.target;
        if (!me) return;
        [me->_session resetNotifyOfPeerKind:me->_peerKind id:me->_peerId hash:me->_peerHash topic:me->_topic completion:^(NSString *errorName) {
            NoshiNotificationsChatController *again = weak.target;
            if (!again) return;
            if (errorName) {
                NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
                return;
            }
            memset(&again->_settings, 0, sizeof(again->_settings));
            [again rebuild];
        }];
    });
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    noshi_notify_decision decision;
    [self effective:&decision];
    int32_t mute = [self effectiveMute];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolBell tone:NoshiSettingsToneRed title:NSLocalizedString(@"notif.chat.mute", nil) subtitle:nil
                                                value:NoshiNotifyMuteText(mute) tap:^{ [(NoshiNotificationsChatController *)weak.target chooseMute]; }]];
    [rows addObject:[NoshiSettingsRow switchRowWithSymbol:NoshiSymbolEye tone:NoshiSettingsToneBlue title:NSLocalizedString(@"notif.preview", nil) subtitle:nil
                                                         on:decision.previews toggle:^(BOOL on) {
        [(NoshiNotificationsChatController *)weak.target edit:^(noshi_peer_notify *s) {
            s->has_previews = 1;
            s->previews = on;
        }];
    }]];
    if (_peerKind == 1) {
        BOOL stories = !(_settings.has_stories_muted && _settings.stories_muted);
        [rows addObject:[NoshiSettingsRow switchRowWithSymbol:NoshiSymbolGallery tone:NoshiSettingsToneOrange title:NSLocalizedString(@"notif.chat.stories", nil)
                                                       subtitle:nil on:stories toggle:^(BOOL on) {
            [(NoshiNotificationsChatController *)weak.target edit:^(noshi_peer_notify *s) {
                s->has_stories_muted = 1;
                s->stories_muted = !on;
            }];
        }]];
    }
    /* the shake of the phone for this chat alone, a setting of this phone: the server has none, so it is kept here */
    int32_t peerKind = _peerKind;
    long long peerId = _peerId;
    [rows addObject:[NoshiSettingsRow switchRowWithSymbol:NoshiSymbolPhone tone:NoshiSettingsToneGreen title:NSLocalizedString(@"notif.chat.vibrate", nil)
                                                   subtitle:NSLocalizedString(@"notif.chat.vibrate.info", nil) on:NoshiNotifyChatVibrates(peerKind, peerId) toggle:^(BOOL on) {
        NoshiNotifySetChatVibrates(peerKind, peerId, on);
    }]];
    noshi_notify_sound shown = decision.sound;
    [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolSettingsSounds tone:NoshiSettingsTonePurple title:NSLocalizedString(@"notif.sound", nil) subtitle:nil
                                                value:NoshiNotifySoundText(_settings.has_sound || decision.sound.kind != NOSHI_SOUND_DEFAULT, &shown)
                                                  tap:^{ [(NoshiNotificationsChatController *)weak.target openSound]; }]];
    NSMutableArray *sections = [NSMutableArray arrayWithObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"notif.chat.header", nil) footer:nil rows:rows]];
    if ([self hasOwnSettings]) {
        NoshiSettingsRow *reset = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolBroom title:NSLocalizedString(@"notif.chat.reset", nil) destructive:YES
                                                                        tap:^{ [(NoshiNotificationsChatController *)weak.target confirmReset]; }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:reset]]];
    }
    self.sections = sections;
}

@end

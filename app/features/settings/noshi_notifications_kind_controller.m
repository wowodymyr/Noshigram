#import "noshi_notifications_kind_controller.h"

#import "noshi_alert.h"
#import "noshi_dialog.h"
#import "noshi_dialog_picker_controller.h"
#import "noshi_notifications_chat_controller.h"
#import "noshi_notifications_sound_controller.h"
#import "noshi_notify_store.h"
#import "noshi_sheet.h"
#import "noshi_weak_reference.h"

@interface NoshiNotificationsKindController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NoshiNotifyKind _kind;
    NSArray *_all;
    BOOL _loadedOnce;
    noshi_reaction_from _lastMessagesFrom;
    noshi_reaction_from _lastStoriesFrom;
}
@end

@implementation NoshiNotificationsKindController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media kind:(NoshiNotifyKind)kind exceptions:(NSArray *)exceptions {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _kind = kind;
    _all = [exceptions retain];
    noshi_reaction_notify reactions = NoshiNotifyReactionsStored();
    _lastMessagesFrom = reactions.messages_from == NOSHI_REACTION_FROM_CONTACTS ? NOSHI_REACTION_FROM_CONTACTS : NOSHI_REACTION_FROM_EVERYONE;
    _lastStoriesFrom = reactions.stories_from == NOSHI_REACTION_FROM_CONTACTS ? NOSHI_REACTION_FROM_CONTACTS : NOSHI_REACTION_FROM_EVERYONE;
    NSString *titles[] = {@"notif.private", @"notif.groups", @"notif.channels", @"notif.stories", @"notif.reactions", @"notif.exceptions.title"};
    self.pageTitle = NSLocalizedString(titles[kind], nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [_all release];
    [super dealloc];
}

- (UIViewController *)controllerAfterThemeChange {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeChanged) name:NoshiNotifyStoreDidChangeNotification object:nil];
    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadExceptions];
}

- (void)storeChanged {
    [self rebuild];
}

- (void)reloadExceptions {
    if (_kind == NoshiNotifyKindReactions) return;
    NoshiWeakReference *weak = _weak;
    [_session loadNotifyExceptionsWithCompletion:^(NSArray *exceptions, NSString *errorName) {
        NoshiNotificationsKindController *me = weak.target;
        if (!me) return;
        if (!exceptions) {
            NSLog(@"noshigram: the notification exceptions did not load: %@", errorName);
            return;
        }
        [me->_all release];
        me->_all = [exceptions retain];
        me->_loadedOnce = YES;
        [me rebuild];
    }];
}

#pragma mark sending

/* stores the new state of a kind and sends it; a refusal puts the old state back */
- (void)changeScope:(void (^)(noshi_peer_notify *settings))change {
    noshi_notify_scope scope = NoshiNotifyScopeOfKind(_kind);
    noshi_peer_notify before = NoshiNotifyScopeStored(scope), after = before;
    change(&after);
    NoshiNotifyScopeStore(scope, &after);
    NoshiWeakReference *weak = _weak;
    [_session sendNotifyScope:scope completion:^(NSString *errorName) {
        if (!errorName) return;
        NSLog(@"noshigram: the notification settings were not kept: %@", errorName);
        NoshiNotifyScopeStore(scope, &before);
        NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
        [(NoshiNotificationsKindController *)weak.target rebuild];
    }];
}

- (void)changeReactions:(void (^)(noshi_reaction_notify *settings))change {
    noshi_reaction_notify before = NoshiNotifyReactionsStored(), after = before;
    change(&after);
    NoshiNotifyReactionsStore(&after);
    NoshiWeakReference *weak = _weak;
    [_session sendReactionNotifyWithCompletion:^(NSString *errorName) {
        if (!errorName) return;
        NSLog(@"noshigram: the reaction settings were not kept: %@", errorName);
        NoshiNotifyReactionsStore(&before);
        NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
        [(NoshiNotificationsKindController *)weak.target rebuild];
    }];
}

#pragma mark rows

- (BOOL)storiesAll {
    noshi_peer_notify s = NoshiNotifyScopeStored(NOSHI_SCOPE_USERS);
    return s.has_stories_muted && !s.stories_muted;
}

- (BOOL)storiesAuto {
    return !NoshiNotifyScopeStored(NOSHI_SCOPE_USERS).has_stories_muted;
}

static NSString *NoshiFromText(int32_t from) {
    if (from == NOSHI_REACTION_FROM_NOBODY) return NSLocalizedString(@"notif.from.nobody", nil);
    return NSLocalizedString(from == NOSHI_REACTION_FROM_CONTACTS ? @"notif.from.contacts" : @"notif.from.everyone", nil);
}

- (void)chooseReactionsFrom:(BOOL)stories {
    NoshiWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.from.pick.everyone", nil), NSLocalizedString(@"notif.from.pick.contacts", nil), nil];
    NoshiSettingsChoose(self, NSLocalizedString(@"notif.from.title", nil), options, ^(NSUInteger index) {
        NoshiNotificationsKindController *me = weak.target;
        noshi_reaction_from from = index == 0 ? NOSHI_REACTION_FROM_EVERYONE : NOSHI_REACTION_FROM_CONTACTS;
        if (stories) me->_lastStoriesFrom = from;
        else me->_lastMessagesFrom = from;
        [me changeReactions:^(noshi_reaction_notify *r) {
            if (stories) r->stories_from = from;
            else r->messages_from = from;
        }];
    });
}

/* the kind is turned off for a while or for good, or on */
- (void)chooseMuteForKind {
    NoshiWeakReference *weak = _weak;
    NSArray *options = [NSArray arrayWithObjects:NSLocalizedString(@"notif.mute.on", nil), NSLocalizedString(@"notif.mute.1h", nil), NSLocalizedString(@"notif.mute.2d", nil),
                        NSLocalizedString(@"notif.mute.off", nil), nil];
    NoshiSettingsChoose(self, nil, options, ^(NSUInteger index) {
        int32_t now = NoshiNotifyNow();
        int32_t until = index == 0 ? 0 : (index == 1 ? now + 3600 : (index == 2 ? now + 48 * 3600 : NOSHI_NOTIFY_MUTE_FOREVER));
        [(NoshiNotificationsKindController *)weak.target changeScope:^(noshi_peer_notify *s) {
            s->has_mute = 1;
            s->mute_until = until;
        }];
    });
}

- (void)openSound {
    NoshiWeakReference *weak = _weak;
    BOOL stories = _kind == NoshiNotifyKindStories, reactions = _kind == NoshiNotifyKindReactions;
    noshi_notify_sound sound;
    BOOL has;
    memset(&sound, 0, sizeof(sound));
    if (reactions) {
        sound = NoshiNotifyReactionsStored().sound;
        has = YES;
    } else {
        noshi_peer_notify s = NoshiNotifyScopeStored(NoshiNotifyScopeOfKind(_kind));
        sound = stories ? s.stories_sound : s.sound;
        has = stories ? s.has_stories_sound : s.has_sound;
    }
    NoshiNotificationsSoundController *page = [[[NoshiNotificationsSoundController alloc] initWithSession:_session media:_media title:self.pageTitle
        current:has ? [NSValue valueWithBytes:&sound objCType:@encode(noshi_notify_sound)] : nil apply:^(noshi_notify_sound picked) {
        NoshiNotificationsKindController *me = weak.target;
        if (!me) return;
        if (reactions) {
            [me changeReactions:^(noshi_reaction_notify *r) { r->sound = picked; }];
        } else {
            [me changeScope:^(noshi_peer_notify *s) {
                if (stories) {
                    s->has_stories_sound = 1;
                    s->stories_sound = picked;
                } else {
                    s->has_sound = 1;
                    s->sound = picked;
                }
            }];
        }
    }] autorelease];
    [self.navigationController pushViewController:page animated:YES];
}

- (NSString *)exceptionLine:(NoshiNotifyException *)exception {
    noshi_peer_notify n = exception.settings;
    if (_kind == NoshiNotifyKindStories) {
        return NSLocalizedString(n.has_stories_muted && n.stories_muted ? @"notif.off" : @"notif.on", nil);
    }
    noshi_peer_notify kind = NoshiNotifyScopeStored(exception.peerKind == 1 ? NOSHI_SCOPE_USERS : (exception.broadcast ? NOSHI_SCOPE_BROADCASTS : NOSHI_SCOPE_CHATS));
    int32_t until = n.has_mute ? n.mute_until : (kind.has_mute ? kind.mute_until : 0);
    return NoshiNotifyMuteText(until);
}

- (NoshiSettingsRow *)rowForException:(NoshiNotifyException *)exception {
    NoshiWeakReference *weak = _weak;
    NSString *title = exception.deleted || !exception.title.length ? NSLocalizedString(@"notif.chat.new", nil) : exception.title;
    if (exception.deleted && exception.title.length == 0) title = [NSString stringWithFormat:@"%lld", exception.peerId];
    return [NoshiSettingsRow rowWithTileImage:NoshiNotifyInitialsTile(exception.title, exception.peerId, 36) title:title subtitle:[self exceptionLine:exception]
                                            tap:^{ [(NoshiNotificationsKindController *)weak.target actOnException:exception]; }];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    BOOL onlyExceptions = _kind == NoshiNotifyKindAllExceptions;
    noshi_notify_scope scope = NoshiNotifyScopeOfKind(_kind);
    noshi_peer_notify stored = NoshiNotifyScopeStored(scope);
    noshi_reaction_notify reactions = NoshiNotifyReactionsStored();
    int32_t now = NoshiNotifyNow();
    if (!onlyExceptions) {
        NSMutableArray *about = [NSMutableArray array];
        NSString *footer = nil;
        if (_kind == NoshiNotifyKindStories) {
            BOOL all = [self storiesAll];
            [about addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.about.stories", nil) subtitle:nil on:all toggle:^(BOOL on) {
                [(NoshiNotificationsKindController *)weak.target changeScope:^(noshi_peer_notify *s) {
                    s->has_stories_muted = 1;
                    s->stories_muted = !on;
                }];
            }]];
            if (!all) {
                [about addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.about.important", nil) subtitle:nil on:[self storiesAuto] toggle:^(BOOL on) {
                    [(NoshiNotificationsKindController *)weak.target changeScope:^(noshi_peer_notify *s) {
                        s->has_stories_muted = on ? 0 : 1;
                        s->stories_muted = on ? 0 : 1;
                    }];
                }]];
            }
            footer = NSLocalizedString(@"notif.about.important.info", nil);
        } else if (_kind == NoshiNotifyKindReactions) {
            NoshiSettingsRow *messages = [NoshiSettingsRow switchRowWithSymbol:NoshiSymbolChats tone:NoshiSettingsToneBlue title:NSLocalizedString(@"notif.about.reactions.messages", nil)
                                                                         subtitle:NoshiFromText(reactions.messages_from) on:reactions.messages_from != NOSHI_REACTION_FROM_NOBODY toggle:^(BOOL on) {
                NoshiNotificationsKindController *me = weak.target;
                [me changeReactions:^(noshi_reaction_notify *r) { r->messages_from = on ? me->_lastMessagesFrom : NOSHI_REACTION_FROM_NOBODY; }];
            }];
            messages.tap = ^{ [(NoshiNotificationsKindController *)weak.target chooseReactionsFrom:NO]; };
            NoshiSettingsRow *stories = [NoshiSettingsRow switchRowWithSymbol:NoshiSymbolGallery tone:NoshiSettingsToneOrange title:NSLocalizedString(@"notif.about.reactions.stories", nil)
                                                                         subtitle:NoshiFromText(reactions.stories_from) on:reactions.stories_from != NOSHI_REACTION_FROM_NOBODY toggle:^(BOOL on) {
                NoshiNotificationsKindController *me = weak.target;
                [me changeReactions:^(noshi_reaction_notify *r) { r->stories_from = on ? me->_lastStoriesFrom : NOSHI_REACTION_FROM_NOBODY; }];
            }];
            stories.tap = ^{ [(NoshiNotificationsKindController *)weak.target chooseReactionsFrom:YES]; };
            [about addObject:messages];
            [about addObject:stories];
        } else {
            NSString *titles[] = {@"notif.about.private", @"notif.about.groups", @"notif.about.channels"};
            BOOL enabled = noshi_notify_mute_state(stored.has_mute ? stored.mute_until : 0, now) == 0;
            [about addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(titles[_kind], nil) subtitle:nil on:enabled toggle:^(BOOL on) {
                NoshiNotificationsKindController *me = weak.target;
                if (on) {
                    [me changeScope:^(noshi_peer_notify *s) {
                        s->has_mute = 1;
                        s->mute_until = 0;
                    }];
                } else {
                    [me rebuild];
                    [me chooseMuteForKind];
                }
            }]];
        }
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"notif.notifyme", nil) footer:footer rows:about]];

        NSMutableArray *options = [NSMutableArray array];
        if (_kind == NoshiNotifyKindStories) {
            [options addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.sendernames", nil) subtitle:nil on:!(stored.has_stories_hide_sender && stored.stories_hide_sender)
                                                               toggle:^(BOOL on) {
                [(NoshiNotificationsKindController *)weak.target changeScope:^(noshi_peer_notify *s) {
                    s->has_stories_hide_sender = 1;
                    s->stories_hide_sender = !on;
                }];
            }]];
        } else if (_kind == NoshiNotifyKindReactions) {
            [options addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.sendernames", nil) subtitle:nil on:reactions.previews toggle:^(BOOL on) {
                [(NoshiNotificationsKindController *)weak.target changeReactions:^(noshi_reaction_notify *r) { r->previews = on; }];
            }]];
        } else {
            [options addObject:[NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"notif.preview", nil) subtitle:nil on:stored.has_previews ? stored.previews : YES toggle:^(BOOL on) {
                [(NoshiNotificationsKindController *)weak.target changeScope:^(noshi_peer_notify *s) {
                    s->has_previews = 1;
                    s->previews = on;
                }];
            }]];
        }
        noshi_notify_sound shown;
        BOOL has;
        if (_kind == NoshiNotifyKindReactions) {
            shown = reactions.sound;
            has = YES;
        } else if (_kind == NoshiNotifyKindStories) {
            shown = stored.stories_sound;
            has = stored.has_stories_sound;
        } else {
            shown = stored.sound;
            has = stored.has_sound;
        }
        [options addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"notif.sound", nil) value:NoshiNotifySoundText(has, &shown)
                                                        tap:^{ [(NoshiNotificationsKindController *)weak.target openSound]; }]];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"notif.settings.header", nil) footer:nil rows:options]];
    }
    if (_kind != NoshiNotifyKindReactions) {
        NSArray *list = NoshiNotifyExceptionsForKind(_all, _kind);
        NSMutableArray *rows = [NSMutableArray array];
        if (!onlyExceptions) {
            [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolPlusCircle tone:NoshiSettingsToneBlue title:NSLocalizedString(@"notif.exceptions.add", nil) subtitle:nil value:nil
                                                          tap:^{ [(NoshiNotificationsKindController *)weak.target addException]; }]];
        }
        for (NoshiNotifyException *exception in list) [rows addObject:[self rowForException:exception]];
        NSString *footer = (onlyExceptions && !list.count && _loadedOnce) ? NSLocalizedString(@"notif.exceptions.empty", nil) : nil;
        if (rows.count) [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:rows]];
        else if (footer) [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:footer rows:[NSArray array]]];
        if (list.count) {
            NoshiSettingsRow *deleteAll = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolTrash title:NSLocalizedString(@"notif.exceptions.deleteall", nil) destructive:YES
                                                                                tap:^{ [(NoshiNotificationsKindController *)weak.target confirmDeleteAll]; }];
            [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:deleteAll]]];
        }
    }
    self.sections = sections;
}

#pragma mark exceptions

- (void)addException {
    NoshiWeakReference *weak = _weak;
    NoshiNotifyKind kind = _kind;
    NoshiDialogPickerController *picker = [[[NoshiDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.limit = 1;
    picker.filter = ^BOOL(NoshiDialog *dialog) {
        if (dialog.folder || dialog.saved || dialog.community || dialog.deleted) return NO;
        if (kind == NoshiNotifyKindPrivate) return dialog.peerKind == 1;
        if (kind == NoshiNotifyKindGroups) return dialog.kind == NOSHI_DIALOG_GROUP;
        if (kind == NoshiNotifyKindChannels) return dialog.kind == NOSHI_DIALOG_CHANNEL;
        return kind == NoshiNotifyKindStories ? dialog.peerKind == 1 : YES;
    };
    picker.pickHandler = ^(NSArray *dialogs) {
        NoshiNotificationsKindController *me = weak.target;
        NoshiDialog *dialog = dialogs.count ? [dialogs objectAtIndex:0] : nil;
        if (!me || !dialog) return;
        if (kind == NoshiNotifyKindStories) {
            /* a person is added to the stories exceptions as one that notifies, or not, against the setting of the kind */
            noshi_peer_notify s;
            memset(&s, 0, sizeof(s));
            s.has_stories_muted = 1;
            s.stories_muted = [me storiesAll] ? 1 : 0;
            [me->_session updateNotify:[NSValue valueWithBytes:&s objCType:@encode(noshi_peer_notify)] ofPeerKind:dialog.peerKind id:dialog.peerId hash:dialog.peerHash topic:0
                            completion:^(NSString *errorName) {
                if (errorName) NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
                [(NoshiNotificationsKindController *)weak.target reloadExceptions];
            }];
            return;
        }
        NoshiNotificationsChatController *page = [[[NoshiNotificationsChatController alloc] initWithSession:me->_session media:me->_media peerKind:dialog.peerKind
                                                                                                         peerId:dialog.peerId peerHash:dialog.peerHash
                                                                                                        channel:dialog.kind == NOSHI_DIALOG_CHANNEL topic:0 title:dialog.title] autorelease];
        [me.navigationController pushViewController:page animated:YES];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)actOnException:(NoshiNotifyException *)exception {
    NoshiWeakReference *weak = _weak;
    BOOL stories = _kind == NoshiNotifyKindStories;
    NSMutableArray *options = [NSMutableArray array];
    noshi_peer_notify n = exception.settings;
    if (stories) {
        BOOL muted = n.has_stories_muted && n.stories_muted;
        [options addObject:NSLocalizedString(muted ? @"notif.story.unmute" : @"notif.story.mute", nil)];
    } else {
        [options addObject:NSLocalizedString(@"notif.exception.customize", nil)];
    }
    [options addObject:NSLocalizedString(@"notif.exception.delete", nil)];
    NoshiSettingsChoose(self, exception.title, options, ^(NSUInteger index) {
        NoshiNotificationsKindController *me = weak.target;
        if (!me) return;
        if (index == 1) {
            [me deleteException:exception];
        } else if (stories) {
            noshi_peer_notify s = exception.settings;
            s.has_stories_muted = 1;
            s.stories_muted = !(n.has_stories_muted && n.stories_muted);
            [me->_session updateNotify:[NSValue valueWithBytes:&s objCType:@encode(noshi_peer_notify)] ofPeerKind:exception.peerKind id:exception.peerId hash:exception.peerHash
                                 topic:0 completion:^(NSString *errorName) {
                if (errorName) NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
                [(NoshiNotificationsKindController *)weak.target reloadExceptions];
            }];
        } else {
            NoshiNotificationsChatController *page = [[[NoshiNotificationsChatController alloc] initWithSession:me->_session media:me->_media peerKind:exception.peerKind
                                                                                                             peerId:exception.peerId peerHash:exception.peerHash
                                                                                                            channel:exception.broadcast topic:0 title:exception.title] autorelease];
            [me.navigationController pushViewController:page animated:YES];
        }
    });
}

- (void)deleteException:(NoshiNotifyException *)exception {
    NoshiWeakReference *weak = _weak;
    [_session resetNotifyOfPeerKind:exception.peerKind id:exception.peerId hash:exception.peerHash topic:0 completion:^(NSString *errorName) {
        if (errorName) NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"notif.error", nil), errorName]);
        [(NoshiNotificationsKindController *)weak.target reloadExceptions];
    }];
}

- (void)confirmDeleteAll {
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"notif.exceptions.deleteall.alert", nil), NSLocalizedString(@"notif.exceptions.deleteall", nil), ^{
        NoshiNotificationsKindController *me = weak.target;
        if (!me) return;
        NSArray *list = NoshiNotifyExceptionsForKind(me->_all, me->_kind);
        __block NSUInteger pending = list.count;
        for (NoshiNotifyException *exception in list) {
            [me->_session resetNotifyOfPeerKind:exception.peerKind id:exception.peerId hash:exception.peerHash topic:0 completion:^(NSString *errorName) {
                if (errorName) NSLog(@"noshigram: an exception was not removed: %@", errorName);
                if (--pending == 0) [(NoshiNotificationsKindController *)weak.target reloadExceptions];
            }];
        }
    });
}

@end

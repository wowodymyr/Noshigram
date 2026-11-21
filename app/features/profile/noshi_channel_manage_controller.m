#import "noshi_channel_manage_controller.h"

#include "noshi_channel.h"

#import "noshi_admin_log_controller.h"
#import "noshi_channel_field_controller.h"
#import "noshi_channel_invites_controller.h"
#import "noshi_channel_errors.h"
#import "noshi_channel_members_controller.h"
#import "noshi_gift_screen.h"
#import "noshi_weak_reference.h"

@interface NoshiChannelManageController () {
    NoshiSession *_session;
    NoshiFullChannel *_channel;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    BOOL _signaturesBusy;
    BOOL _protectBusy;
    void (^_changedHandler)(NoshiFullChannel *channel);
}
@end

@implementation NoshiChannelManageController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _channel = [channel retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(channel.megagroup ? @"channel.manage.title.group" : @"channel.manage.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_channel release];
    [_avatars release];
    [_media release];
    [_changedHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    /* the counts and rights shown on opening came with the profile; the server may have moved on since */
    [self refresh];
}

#pragma mark content

static NSString *NoshiCount(NSInteger count) {
    return count > 0 ? [NSString stringWithFormat:@"%ld", (long)count] : nil;
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NoshiFullChannel *channel = _channel;
    uint32_t rights = channel.adminRights;
    NSMutableArray *sections = [NSMutableArray array];

    if (rights & NOSHI_ADMIN_CHANGE_INFO) {
        NSMutableArray *rows = [NSMutableArray array];
        [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolCompose tone:NoshiSettingsToneBlue title:NSLocalizedString(@"channel.field.title", nil)
                                                 subtitle:nil value:channel.dialog.title tap:^{ [(NoshiChannelManageController *)weak.target editTitle]; }]];
        NSString *about = channel.about.length ? channel.about : NSLocalizedString(@"channel.about.none", nil);
        [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolInfo tone:NoshiSettingsToneCyan title:NSLocalizedString(@"channel.field.about", nil)
                                                 subtitle:about value:nil tap:^{ [(NoshiChannelManageController *)weak.target editAbout]; }]];
        /* only the creator decides whether the channel is public */
        if (channel.creator) {
            NSString *link = channel.username.length ? [@"t.me/" stringByAppendingString:channel.username] : NSLocalizedString(@"channel.kind.private", nil);
            [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolLink tone:NoshiSettingsToneGreen title:NSLocalizedString(@"channel.field.link", nil)
                                                     subtitle:nil value:link tap:^{ [(NoshiChannelManageController *)weak.target editUsername]; }]];
        }
        if (!channel.megagroup) {
            [rows addObject:[NoshiSettingsRow switchRowWithSymbol:NoshiSymbolPerson tone:NoshiSettingsToneOrange title:NSLocalizedString(@"channel.signatures", nil)
                                                           subtitle:NSLocalizedString(@"channel.signatures.info", nil) on:channel.signatures toggle:^(BOOL on) {
                [(NoshiChannelManageController *)weak.target setSignatures:on];
            }]];
        }
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"channel.manage.info", nil) footer:nil rows:rows]];
    }

    /* the creator and the admins who may invite make links, whether the channel is public or private */
    if (channel.creator || (rights & NOSHI_ADMIN_INVITE_USERS)) {
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:
            [NoshiSettingsRow rowWithSymbol:NoshiSymbolLink tone:NoshiSettingsToneBlueLight title:NSLocalizedString(@"channel.manage.invites", nil) subtitle:nil value:nil tap:^{
                [(NoshiChannelManageController *)weak.target openInvites];
            }]]]];
    }

    /* only the creator decides whether members may forward, copy and save */
    if (channel.creator) {
        NoshiSettingsRow *protect = [NoshiSettingsRow switchRowWithSymbol:NoshiSymbolBlock tone:NoshiSettingsToneRed title:NSLocalizedString(@"channel.protect", nil) subtitle:nil
                                                                           on:channel.dialog.noForwards toggle:^(BOOL on) {
            [(NoshiChannelManageController *)weak.target setContentProtected:on];
        }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"channel.protect.header", nil)
                                                               footer:NSLocalizedString(channel.megagroup ? @"channel.protect.info.group" : @"channel.protect.info", nil)
                                                                 rows:[NSArray arrayWithObject:protect]]];
    }

    NSMutableArray *people = [NSMutableArray array];
    [people addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolMember tone:NoshiSettingsToneBlueDeep
                                                  title:NSLocalizedString(channel.megagroup ? @"channel.members" : @"channel.subscribers", nil) subtitle:nil
                                                  value:NoshiCount(channel.participants) tap:^{
        [(NoshiChannelManageController *)weak.target openList:NoshiChannelListSubscribers];
    }]];
    [people addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolStar tone:NoshiSettingsToneOrangeBright title:NSLocalizedString(@"channel.admins", nil) subtitle:nil
                                                  value:NoshiCount(channel.admins) tap:^{
        [(NoshiChannelManageController *)weak.target openList:NoshiChannelListAdmins];
    }]];
    if (rights & NOSHI_ADMIN_BAN_USERS) {
        [people addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolBlock tone:NoshiSettingsToneRed title:NSLocalizedString(@"channel.banned", nil) subtitle:nil
                                                      value:NoshiCount(channel.banned) tap:^{
            [(NoshiChannelManageController *)weak.target openList:NoshiChannelListBlacklist];
        }]];
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"channel.manage.people", nil) footer:nil rows:people]];
    NSMutableArray *history = [NSMutableArray array];
    [history addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolClock tone:NoshiSettingsToneCyan title:NSLocalizedString(@"adminlog.title", nil) subtitle:nil
                                                   value:nil tap:^{ [(NoshiChannelManageController *)weak.target openAdminLog]; }]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"adminlog.footer", nil) rows:history]];
    self.sections = sections;
    [self reloadSettings];
}

- (void)refresh {
    NoshiWeakReference *weak = _weak;
    [self retain];
    [_session loadFullChannelOfDialog:_channel.dialog completion:^(NoshiFullChannel *channel, NSString *errorName) {
        [self autorelease];
        NoshiChannelManageController *me = weak.target;
        if (!me) return;
        if (!channel) {
            NSLog(@"noshigram: the channel %lld did not reload: %@", me->_channel.dialog.peerId, errorName);
            return;
        }
        [me->_channel release];
        me->_channel = [channel retain];
        [me rebuild];
        if (me->_changedHandler) me->_changedHandler(channel);
    }];
}

#pragma mark editing

/* an answer that says the value is already what was asked for is not a failure */
static NSString *NoshiUnlessUnchanged(NSString *errorName) {
    if ([errorName isEqualToString:@"CHAT_NOT_MODIFIED"] || [errorName isEqualToString:@"CHAT_ABOUT_NOT_MODIFIED"] ||
        [errorName isEqualToString:@"USERNAME_NOT_MODIFIED"] || [errorName isEqualToString:@"NOT_MODIFIED"]) return nil;
    return errorName;
}

- (void)pushField:(NoshiChannelFieldKind)kind text:(NSString *)text save:(void (^)(NSString *text, void (^done)(NSString *errorName)))save {
    NoshiChannelFieldController *field = [[[NoshiChannelFieldController alloc] initWithSession:_session avatars:_avatars media:_media kind:kind text:text
                                                                                            dialog:_channel.dialog save:save] autorelease];
    [self.navigationController pushViewController:field animated:YES];
}

/* the write finished: the profile list shows the new title, and this screen asks the server for the rest */
- (void)writeDone:(NSString *)errorName {
    if (errorName) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiDialogsChangedNotification object:nil];
    [self refresh];
}

- (void)editTitle {
    NoshiWeakReference *weak = _weak;
    [self pushField:NoshiChannelFieldTitle text:_channel.dialog.title save:^(NSString *text, void (^done)(NSString *)) {
        NoshiChannelManageController *me = weak.target;
        if (!me) { done(nil); return; }
        [me->_session setTitle:text ofDialog:me->_channel.dialog completion:^(NSString *errorName) {
            NSString *error = NoshiUnlessUnchanged(errorName);
            [(NoshiChannelManageController *)weak.target writeDone:error];
            done(error);
        }];
    }];
}

- (void)editAbout {
    NoshiWeakReference *weak = _weak;
    [self pushField:NoshiChannelFieldAbout text:_channel.about save:^(NSString *text, void (^done)(NSString *)) {
        NoshiChannelManageController *me = weak.target;
        if (!me) { done(nil); return; }
        [me->_session setAbout:text ofDialog:me->_channel.dialog completion:^(NSString *errorName) {
            NSString *error = NoshiUnlessUnchanged(errorName);
            [(NoshiChannelManageController *)weak.target writeDone:error];
            done(error);
        }];
    }];
}

- (void)editUsername {
    NoshiWeakReference *weak = _weak;
    [self pushField:NoshiChannelFieldUsername text:_channel.username save:^(NSString *text, void (^done)(NSString *)) {
        NoshiChannelManageController *me = weak.target;
        if (!me) { done(nil); return; }
        [me->_session setUsername:text ofDialog:me->_channel.dialog completion:^(NSString *errorName) {
            NSString *error = NoshiUnlessUnchanged(errorName);
            [(NoshiChannelManageController *)weak.target writeDone:error];
            done(error);
        }];
    }];
}

- (void)setSignatures:(BOOL)enabled {
    if (_signaturesBusy) return;
    _signaturesBusy = YES;
    NoshiWeakReference *weak = _weak;
    [self retain];
    [_session setSignatures:enabled ofDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        NoshiChannelManageController *me = weak.target;
        if (!me) return;
        me->_signaturesBusy = NO;
        NSString *error = NoshiUnlessUnchanged(errorName);
        if (error) NoshiGiftAlert(nil, NoshiChannelErrorText(error));
        /* a failed switch goes back to what the server has, a good one is confirmed by it */
        [me refresh];
    }];
}

- (void)setContentProtected:(BOOL)enabled {
    if (_protectBusy) return;
    _protectBusy = YES;
    NoshiWeakReference *weak = _weak;
    [self retain];
    [_session setContentProtected:enabled ofDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        NoshiChannelManageController *me = weak.target;
        if (!me) return;
        me->_protectBusy = NO;
        NSString *error = NoshiUnlessUnchanged(errorName);
        if (error) NoshiGiftAlert(nil, NoshiChannelErrorText(error));
        /* the switch shows what the server has, whether the change went through or not */
        [me refresh];
    }];
}

#pragma mark lists

- (void)openAdminLog {
    NoshiAdminLogController *log = [[[NoshiAdminLogController alloc] initWithSession:_session channel:_channel avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:log animated:YES];
}

- (void)openInvites {
    NoshiChannelInvitesController *invites = [[[NoshiChannelInvitesController alloc] initWithSession:_session channel:_channel avatars:_avatars media:_media] autorelease];
    [self.navigationController pushViewController:invites animated:YES];
}

- (void)openList:(NoshiChannelList)list {
    NoshiChannelMembersController *members = [[[NoshiChannelMembersController alloc] initWithSession:_session channel:_channel list:list avatars:_avatars
                                                                                                   media:_media] autorelease];
    NoshiWeakReference *weak = _weak;
    members.changedHandler = ^{ [(NoshiChannelManageController *)weak.target refresh]; };
    [self.navigationController pushViewController:members animated:YES];
}

@end

#import "noshi_channel_rights_controller.h"

#include "noshi_channel.h"

#import "noshi_channel_field_controller.h"
#import "noshi_channel_errors.h"
#import "noshi_gift_screen.h"
#import "noshi_sheet.h"
#import "noshi_weak_reference.h"

typedef struct {
    uint32_t bit;
    const char *key;
} NoshiRightEntry;

/* the rights of a broadcast channel, in the order lists them */
static const NoshiRightEntry NoshiChannelRights[] = {
    {NOSHI_ADMIN_CHANGE_INFO, "channel.right.info"},
    {NOSHI_ADMIN_POST_MESSAGES, "channel.right.post"},
    {NOSHI_ADMIN_EDIT_MESSAGES, "channel.right.edit"},
    {NOSHI_ADMIN_DELETE_MESSAGES, "channel.right.delete"},
    {NOSHI_ADMIN_INVITE_USERS, "channel.right.invite"},
    {NOSHI_ADMIN_MANAGE_CALL, "channel.right.call"},
    {NOSHI_ADMIN_ADD_ADMINS, "channel.right.admins"},
};

/* and of a group */
static const NoshiRightEntry NoshiGroupRights[] = {
    {NOSHI_ADMIN_CHANGE_INFO, "group.right.info"},
    {NOSHI_ADMIN_DELETE_MESSAGES, "channel.right.delete"},
    {NOSHI_ADMIN_BAN_USERS, "group.right.ban"},
    {NOSHI_ADMIN_INVITE_USERS, "group.right.invite"},
    {NOSHI_ADMIN_PIN_MESSAGES, "group.right.pin"},
    {NOSHI_ADMIN_MANAGE_CALL, "group.right.call"},
    {NOSHI_ADMIN_ANONYMOUS, "group.right.anonymous"},
    {NOSHI_ADMIN_ADD_ADMINS, "channel.right.admins"},
};

/* what a new admin starts with: the usual set, without the right to appoint others and to hide behind the group */
#define NEW_ADMIN_BASE (NOSHI_ADMIN_ALL & ~(NOSHI_ADMIN_ADD_ADMINS | NOSHI_ADMIN_ANONYMOUS | NOSHI_ADMIN_MANAGE_TOPICS))

@interface NoshiChannelRightsController () {
    NoshiSession *_session;
    NoshiFullChannel *_channel;
    NoshiPerson *_person;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NSString *_rank;
    uint32_t _rights;
    uint32_t _grantable;
    BOOL _isAdmin;
    BOOL _busy;
    void (^_changedHandler)(void);
}
@end

@implementation NoshiChannelRightsController

@synthesize changedHandler = _changedHandler;

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel person:(NoshiPerson *)person rights:(uint32_t)rights
                 rank:(NSString *)rank isAdmin:(BOOL)isAdmin avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _channel = [channel retain];
    _person = [person retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _isAdmin = isAdmin;
    _rank = [rank copy];
    /* only what the account holds can be handed on; the creator holds everything */
    _grantable = channel.creator ? NOSHI_ADMIN_ALL : channel.adminRights;
    _rights = isAdmin ? rights : (NEW_ADMIN_BASE & _grantable);
    self.pageTitle = NSLocalizedString(@"channel.rights.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_channel release];
    [_person release];
    [_avatars release];
    [_media release];
    [_rank release];
    [_changedHandler release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    NoshiSettingsRow *who = [NoshiSettingsRow rowWithTitle:_person.name subtitle:_person.username.length ? [@"@" stringByAppendingString:_person.username] : nil
                                                         value:NSLocalizedString(_isAdmin ? @"channel.role.admin" : @"channel.role.member", nil) tap:nil];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:who]]];

    BOOL group = _channel.megagroup;
    const NoshiRightEntry *table = group ? NoshiGroupRights : NoshiChannelRights;
    size_t count = group ? sizeof(NoshiGroupRights) / sizeof(NoshiGroupRights[0]) : sizeof(NoshiChannelRights) / sizeof(NoshiChannelRights[0]);
    NSMutableArray *rights = [NSMutableArray array];
    for (size_t i = 0; i < count; ++i) {
        uint32_t bit = table[i].bit;
        NoshiSettingsRow *row = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString([NSString stringWithUTF8String:table[i].key], nil) subtitle:nil
                                                                      on:(_rights & bit) != 0 toggle:^(BOOL on) {
            NoshiChannelRightsController *me = weak.target;
            if (!me) return;
            if (on) me->_rights |= bit;
            else me->_rights &= ~bit;
        }];
        row.disabled = (_grantable & bit) == 0;
        [rights addObject:row];
    }
    NSString *footer = _grantable == NOSHI_ADMIN_ALL ? nil : NSLocalizedString(@"channel.rights.footer", nil);
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"channel.rights.header", nil) footer:footer rows:rights]];

    NoshiSettingsRow *rank = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"channel.rights.rank", nil)
                                                          value:_rank.length ? _rank : NSLocalizedString(@"channel.rights.rank.none", nil) tap:^{
        [(NoshiChannelRightsController *)weak.target editRank];
    }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"channel.rank.hint", nil) rows:[NSArray arrayWithObject:rank]]];

    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolCheck title:NSLocalizedString(@"channel.save", nil) destructive:NO tap:^{
        [(NoshiChannelRightsController *)weak.target save];
    }]];
    if (_isAdmin) {
        [actions addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolLogout title:NSLocalizedString(@"channel.rights.dismiss", nil) destructive:YES tap:^{
            [(NoshiChannelRightsController *)weak.target askDismiss];
        }]];
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:actions]];
    self.sections = sections;
    [self reloadSettings];
}

- (void)editRank {
    NoshiWeakReference *weak = _weak;
    NoshiChannelFieldController *field = [[[NoshiChannelFieldController alloc] initWithSession:_session avatars:_avatars media:_media
                                                                                               kind:NoshiChannelFieldRank text:_rank dialog:nil
                                                                                               save:^(NSString *text, void (^done)(NSString *)) {
        NoshiChannelRightsController *me = weak.target;
        if (me) {
            [me->_rank release];
            me->_rank = [text copy];
            [me rebuild];
        }
        /* the title is sent with the rights, so there is nothing to ask the server yet */
        done(nil);
    }] autorelease];
    [self.navigationController pushViewController:field animated:YES];
}

- (void)finishWithError:(NSString *)errorName {
    _busy = NO;
    if (errorName) {
        NoshiGiftAlert(nil, NoshiChannelErrorText(errorName));
        return;
    }
    if (_changedHandler) _changedHandler();
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)save {
    if (_busy) return;
    /* an admin with no right left is a subscriber again, which has its own way out */
    if (!_rights) {
        NoshiGiftAlert(nil, NSLocalizedString(@"channel.rights.none", nil));
        return;
    }
    _busy = YES;
    [self retain];
    [_session setAdminRights:_rights rank:_rank ofPerson:_person inDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        [self finishWithError:errorName];
    }];
}

- (void)askDismiss {
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, [NSString stringWithFormat:NSLocalizedString(@"channel.rights.dismiss.confirm", nil), _person.name],
                         NSLocalizedString(@"channel.rights.dismiss", nil), ^{ [(NoshiChannelRightsController *)weak.target dismissNow]; });
}

- (void)dismissNow {
    if (_busy) return;
    _busy = YES;
    [self retain];
    [_session setAdminRights:0 rank:nil ofPerson:_person inDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        [self finishWithError:errorName];
    }];
}

@end

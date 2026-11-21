#import "noshi_channel_invites_controller.h"

#import "noshi_alert.h"
#import "noshi_channel_errors.h"
#import "noshi_channel_invite_edit_controller.h"
#import "noshi_gift_screen.h"
#import "noshi_sheet.h"
#import "noshi_weak_reference.h"

@interface NoshiChannelInvitesController () {
    NoshiSession *_session;
    NoshiFullChannel *_channel;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    NSMutableArray *_live;
    NSMutableArray *_revoked;
    NSInteger _liveTotal;
    NSInteger _revokedTotal;
    BOOL _loadingLive;
    BOOL _loadingRevoked;
    BOOL _loadedLive;
    BOOL _loadedRevoked;
    BOOL _busy;
}
@end

@implementation NoshiChannelInvitesController

- (id)initWithSession:(NoshiSession *)session channel:(NoshiFullChannel *)channel avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _channel = [channel retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    _live = [[NSMutableArray alloc] init];
    _revoked = [[NSMutableArray alloc] init];
    self.pageTitle = NSLocalizedString(@"invite.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_channel release];
    [_avatars release];
    [_media release];
    [_live release];
    [_revoked release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
    [self loadMore:NO];
    [self loadMore:YES];
}

#pragma mark loading

/* the next page of one list; the first page replaces what the list holds, so a reload does not stack the same links twice */
- (void)loadMore:(BOOL)revoked {
    if (revoked ? _loadingRevoked : _loadingLive) return;
    NSMutableArray *list = revoked ? _revoked : _live;
    BOOL first = revoked ? !_loadedRevoked : !_loadedLive;
    if (revoked) _loadingRevoked = YES; else _loadingLive = YES;
    NoshiWeakReference *weak = _weak;
    [self retain];
    [_session loadInvitesOfDialog:_channel.dialog revoked:revoked afterInvite:first ? nil : [list lastObject]
                       completion:^(NSArray *invites, NSInteger total, NSString *errorName) {
        [self autorelease];
        NoshiChannelInvitesController *me = weak.target;
        if (!me) return;
        if (revoked) me->_loadingRevoked = NO; else me->_loadingLive = NO;
        if (errorName) {
            NSLog(@"noshigram: invite links of channel %lld did not load: %@", me->_channel.dialog.peerId, errorName);
            [me showError:errorName];
            return;
        }
        NSMutableArray *target = revoked ? me->_revoked : me->_live;
        if (first) [target removeAllObjects];
        [target addObjectsFromArray:invites];
        if (revoked) { me->_revokedTotal = total; me->_loadedRevoked = YES; } else { me->_liveTotal = total; me->_loadedLive = YES; }
        [me rebuild];
    }];
}

- (void)showError:(NSString *)errorName {
    NoshiGiftAlert(nil, NoshiChannelErrorText(errorName));
}

#pragma mark rows

static NSString *NoshiInviteDate(int32_t date) {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date]];
}

static NSString *NoshiInviteShortLink(NSString *link) {
    for (NSString *prefix in [NSArray arrayWithObjects:@"https://", @"http://", nil]) {
        if ([link hasPrefix:prefix]) return [link substringFromIndex:prefix.length];
    }
    return link;
}

/* the line under a link: who joined through it, how many joins are left and when it ends */
static NSString *NoshiInviteDetails(NoshiInvite *invite) {
    NSMutableArray *parts = [NSMutableArray array];
    if (invite.usage > 0) [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"invite.joined", nil), (int)invite.usage]];
    else if (!invite.requestNeeded) [parts addObject:NSLocalizedString(@"invite.joined.none", nil)];
    if (invite.requestNeeded) [parts addObject:invite.requested > 0 ? [NSString stringWithFormat:NSLocalizedString(@"invite.requested", nil), (int)invite.requested]
                                                                    : NSLocalizedString(@"invite.approval", nil)];
    if (invite.usageLimit > 0 && !invite.revoked) [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"invite.limit", nil), (int)invite.usageLimit]];
    if (invite.expired) [parts addObject:NSLocalizedString(@"invite.expired", nil)];
    else if (invite.expireDate > 0 && !invite.revoked) [parts addObject:[NSString stringWithFormat:NSLocalizedString(@"invite.expires", nil), NoshiInviteDate(invite.expireDate)]];
    return [parts componentsJoinedByString:@" · "];
}

static NSString *NoshiInviteName(NoshiInvite *invite) {
    if (invite.title.length) return invite.title;
    if (invite.permanent) return NSLocalizedString(@"invite.primary", nil);
    return NoshiInviteShortLink(invite.link);
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolPlusCircle title:NSLocalizedString(@"invite.create", nil) destructive:NO tap:^{
        [(NoshiChannelInvitesController *)weak.target createLink];
    }]];
    for (NoshiInvite *invite in _live) {
        NoshiSettingsTone tone = invite.expired ? NoshiSettingsToneGray : (invite.requestNeeded ? NoshiSettingsToneOrange : NoshiSettingsToneGreen);
        [rows addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolLink tone:tone title:NoshiInviteName(invite) subtitle:NoshiInviteDetails(invite) value:nil tap:^{
            [(NoshiChannelInvitesController *)weak.target showActionsOfInvite:invite];
        }]];
    }
    if (_live.count < (NSUInteger)_liveTotal) {
        [rows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"invite.more", nil) value:nil tap:^{
            [(NoshiChannelInvitesController *)weak.target loadMore:NO];
        }]];
    }
    NSString *footer = NSLocalizedString(_channel.megagroup ? @"invite.footer.group" : @"invite.footer.channel", nil);
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"invite.live", nil) footer:footer rows:rows]];
    if (_revoked.count) {
        NSMutableArray *gone = [NSMutableArray array];
        for (NoshiInvite *invite in _revoked) {
            [gone addObject:[NoshiSettingsRow rowWithSymbol:NoshiSymbolLink tone:NoshiSettingsToneGray title:NoshiInviteName(invite) subtitle:NoshiInviteDetails(invite) value:nil tap:^{
                [(NoshiChannelInvitesController *)weak.target showActionsOfInvite:invite];
            }]];
        }
        if (_revoked.count < (NSUInteger)_revokedTotal) {
            [gone addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"invite.more", nil) value:nil tap:^{
                [(NoshiChannelInvitesController *)weak.target loadMore:YES];
            }]];
        }
        [gone addObject:[NoshiSettingsRow actionRowWithSymbol:NoshiSymbolTrash title:NSLocalizedString(@"invite.delete.all", nil) destructive:YES tap:^{
            [(NoshiChannelInvitesController *)weak.target confirmDeleteAllRevoked];
        }]];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"invite.revoked", nil) footer:nil rows:gone]];
    }
    self.sections = sections;
    [self reloadSettings];
}

#pragma mark actions

- (void)showActionsOfInvite:(NoshiInvite *)invite {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *options = [NSMutableArray array];
    NSMutableArray *kinds = [NSMutableArray array];
    if (!invite.revoked) {
        [options addObject:NSLocalizedString(@"invite.action.copy", nil)]; [kinds addObject:@"copy"];
        if (NSClassFromString(@"UIActivityViewController")) { [options addObject:NSLocalizedString(@"invite.action.share", nil)]; [kinds addObject:@"share"]; }
        [options addObject:NSLocalizedString(@"invite.action.edit", nil)]; [kinds addObject:@"edit"];
        [options addObject:NSLocalizedString(@"invite.action.revoke", nil)]; [kinds addObject:@"revoke"];
    } else {
        [options addObject:NSLocalizedString(@"invite.action.delete", nil)]; [kinds addObject:@"delete"];
    }
    NoshiSettingsChoose(self, NoshiInviteShortLink(invite.link), options, ^(NSUInteger index) {
        NoshiChannelInvitesController *me = weak.target;
        if (!me || index >= kinds.count) return;
        NSString *kind = [kinds objectAtIndex:index];
        if ([kind isEqualToString:@"copy"]) [me copyInvite:invite];
        else if ([kind isEqualToString:@"share"]) [me shareInvite:invite];
        else if ([kind isEqualToString:@"edit"]) [me editInvite:invite];
        else if ([kind isEqualToString:@"revoke"]) [me confirmRevoke:invite];
        else [me deleteInvite:invite];
    });
}

- (void)copyInvite:(NoshiInvite *)invite {
    [UIPasteboard generalPasteboard].string = invite.link;
    NoshiShowNotice(nil, NSLocalizedString(@"invite.copied", nil));
}

- (void)shareInvite:(NoshiInvite *)invite {
    Class activityClass = NSClassFromString(@"UIActivityViewController");
    if (!activityClass) return;
    id activity = [[[activityClass alloc] initWithActivityItems:[NSArray arrayWithObject:invite.link] applicationActivities:nil] autorelease];
    /* an ipad shows the sheet as a popover, which needs a place to point at */
    if ([activity respondsToSelector:NSSelectorFromString(@"popoverPresentationController")]) {
        id popover = [activity performSelector:NSSelectorFromString(@"popoverPresentationController")];
        [popover setValue:self.view forKey:@"sourceView"];
        [popover setValue:[NSValue valueWithCGRect:CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1)] forKey:@"sourceRect"];
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)createLink {
    [self openEditorFor:nil];
}

- (void)editInvite:(NoshiInvite *)invite {
    [self openEditorFor:invite];
}

- (void)openEditorFor:(NoshiInvite *)invite {
    NoshiWeakReference *weak = _weak;
    NoshiChannelInviteEditController *editor = [[[NoshiChannelInviteEditController alloc] initWithSession:_session channel:_channel invite:invite
                                                                                                         saved:^(NoshiInvite *saved) {
        [(NoshiChannelInvitesController *)weak.target inviteSaved:saved replacing:invite];
    }] autorelease];
    [self.navigationController pushViewController:editor animated:YES];
}

/* a made or changed link goes where the server put it, without asking for both lists again */
- (void)inviteSaved:(NoshiInvite *)saved replacing:(NoshiInvite *)old {
    NSUInteger at = old ? [_live indexOfObject:old] : NSNotFound;
    if (at != NSNotFound) [_live replaceObjectAtIndex:at withObject:saved];
    else {
        [_live insertObject:saved atIndex:0];
        ++_liveTotal;
    }
    [self rebuild];
}

- (void)confirmRevoke:(NoshiInvite *)invite {
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"invite.revoke.confirm", nil), NSLocalizedString(@"invite.action.revoke", nil), ^{
        [(NoshiChannelInvitesController *)weak.target revokeInvite:invite];
    });
}

- (void)revokeInvite:(NoshiInvite *)invite {
    if (_busy) return;
    _busy = YES;
    NoshiWeakReference *weak = _weak;
    [self retain];
    [_session revokeInvite:invite inDialog:_channel.dialog completion:^(NoshiInvite *revoked, NoshiInvite *replacement, NSString *errorName) {
        [self autorelease];
        NoshiChannelInvitesController *me = weak.target;
        if (!me) return;
        me->_busy = NO;
        if (errorName) {
            [me showError:errorName];
            return;
        }
        [me->_live removeObject:invite];
        if (me->_liveTotal > 0) --me->_liveTotal;
        if (revoked) {
            [me->_revoked insertObject:revoked atIndex:0];
            ++me->_revokedTotal;
        }
        /* revoking the link a chat was made with makes the server put a new one in its place */
        if (replacement) {
            [me->_live insertObject:replacement atIndex:0];
            ++me->_liveTotal;
        }
        [me rebuild];
    }];
}

- (void)deleteInvite:(NoshiInvite *)invite {
    if (_busy) return;
    _busy = YES;
    NoshiWeakReference *weak = _weak;
    [self retain];
    [_session deleteInvite:invite inDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        NoshiChannelInvitesController *me = weak.target;
        if (!me) return;
        me->_busy = NO;
        if (errorName) {
            [me showError:errorName];
            return;
        }
        [me->_revoked removeObject:invite];
        if (me->_revokedTotal > 0) --me->_revokedTotal;
        [me rebuild];
    }];
}

- (void)confirmDeleteAllRevoked {
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"invite.delete.all.confirm", nil), NSLocalizedString(@"invite.delete.all", nil), ^{
        [(NoshiChannelInvitesController *)weak.target deleteAllRevoked];
    });
}

- (void)deleteAllRevoked {
    if (_busy) return;
    _busy = YES;
    NoshiWeakReference *weak = _weak;
    [self retain];
    [_session deleteRevokedInvitesInDialog:_channel.dialog completion:^(NSString *errorName) {
        [self autorelease];
        NoshiChannelInvitesController *me = weak.target;
        if (!me) return;
        me->_busy = NO;
        if (errorName) {
            [me showError:errorName];
            return;
        }
        [me->_revoked removeAllObjects];
        me->_revokedTotal = 0;
        [me rebuild];
    }];
}

@end

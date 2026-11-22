#import "noshi_chats_menu.h"

#import "noshi_alert.h"
#import "noshi_alert_view.h"
#import "noshi_classic_contacts_controller.h"
#import "noshi_people_select_controller.h"
#import "noshi_session_channels.h"

enum { NoshiComposeChannelAlert = 2, NoshiComposeGroupAlert = 3 };

@interface NoshiChatsMenu () {
    NoshiSession *_session;
    UIViewController *_host;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    void (^_refresh)(void);
    /* the people picked for a new group while its name is asked for */
    NSArray *_groupPeople;
}
@end

@implementation NoshiChatsMenu

- (id)initWithSession:(NoshiSession *)session host:(UIViewController *)host avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
             stickers:(NoshiStickerLibrary *)stickers refresh:(void (^)(void))refresh {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _host = host;
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    _refresh = [refresh copy];
    return self;
}

- (void)dealloc {
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [_refresh release];
    [_groupPeople release];
    [super dealloc];
}

- (void)openCompose {
    NoshiClassicContactsController *compose = [[[NoshiClassicContactsController alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers] autorelease];
    /* the screen keeps the blocks, and with them this object, for as long as it is open */
    [compose setComposeNewGroup:^{ [self chooseGroupPeople]; } newChannel:^{ [self askNameWithTitle:NSLocalizedString(@"create.channel.title", nil) tag:NoshiComposeChannelAlert]; }];
    compose.hidesBottomBarWhenPushed = YES;
    [_host.navigationController pushViewController:compose animated:YES];
}

/* the people of the group are picked first, and the name is asked for when the page of the picks is left with some of them */
- (void)chooseGroupPeople {
    NoshiPeopleSelectController *select = [[[NoshiPeopleSelectController alloc] initWithSession:_session title:NSLocalizedString(@"compose.group", nil) chosen:nil
                                                                                            done:^(NSArray *people) {
        if (!people.count) return;
        [_groupPeople release];
        _groupPeople = [people copy];
        [self askNameWithTitle:NSLocalizedString(@"create.group.title", nil) tag:NoshiComposeGroupAlert];
    }] autorelease];
    [select useNextKeyWithTitle:NSLocalizedString(@"compose.next", nil)];
    [_host.navigationController pushViewController:select animated:YES];
}

- (void)askNameWithTitle:(NSString *)title tag:(NSInteger)tag {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:title message:nil delegate:self
                               cancelButtonTitle:NSLocalizedString(@"attach.cancel", nil) otherButtonTitles:NSLocalizedString(@"create.action", nil), nil];
    [alert setValue:[NSNumber numberWithInt:2] forKey:@"alertViewStyle"];
    [[alert textFieldAtIndex:0] setPlaceholder:NSLocalizedString(@"create.name", nil)];
    [alert setTag:tag];
    /* the alert keeps no reference to its delegate, so this object stays until its answer */
    [self retain];
    [alert show];
    [alert release];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSString *name = [[[alertView textFieldAtIndex:0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (buttonIndex == alertView.cancelButtonIndex || !name.length) {
        [self autorelease];
        return;
    }
    void (^finished)(NSString *) = ^(NSString *errorName) {
        if (errorName) {
            NoshiShowNotice(nil, [NSString stringWithFormat:NSLocalizedString(@"create.failed", nil), errorName]);
        } else {
            /* the new chat heads the list the person comes back to */
            [_host.navigationController popToViewController:_host animated:YES];
            if (_refresh) _refresh();
        }
        [self autorelease];
    };
    if (alertView.tag == NoshiComposeGroupAlert) [_session createGroupTitled:name people:_groupPeople completion:finished];
    else [_session createChannelTitled:name megagroup:NO completion:finished];
}

@end

#import "noshi_chats_menu.h"

#import "noshi_alert.h"
#import "noshi_alert_view.h"
#import "noshi_bookmarks_controller.h"
#import "noshi_chat_controller.h"
#import "noshi_dialog.h"
#import "noshi_more_settings_controller.h"
#import "noshi_person.h"
#import "noshi_popup_menu.h"
#import "noshi_proxy_settings.h"
#import "noshi_session_channels.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#include "noshi_proxy.h"

@interface NoshiChatsMenu () {
    NoshiSession *_session;
    UIViewController *_host;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    void (^_refresh)(void);
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
    [super dealloc];
}

- (void)showFailureText:(NSString *)text {
    NoshiShowNotice(nil, text);
}

- (void)showInView:(UIView *)view anchor:(CGPoint)anchor {
    BOOL dark = NoshiThemeIsDark();
    /* the list of proxies is one tap away only while one is on, which is when the connection may need it changed */
    noshi_proxy proxy;
    BOOL proxyEnabled = NO;
    noshi_status proxyStatus = NoshiProxyRead(&proxy, &proxyEnabled);
    noshi_wipe(&proxy, sizeof(proxy));
    if (proxyStatus != NOSHI_OK) NSLog(@"noshigram: proxy settings unavailable: %s", noshi_status_name(proxyStatus));
    NSMutableArray *titles = [NSMutableArray arrayWithObjects:NSLocalizedString(dark ? @"menu.day" : @"menu.night", nil), NSLocalizedString(@"menu.group", nil),
                              NSLocalizedString(@"menu.channel", nil), NSLocalizedString(@"menu.saved", nil), NSLocalizedString(@"bookmarks.title", nil), nil];
    NoshiSymbol symbols[] = {dark ? NoshiSymbolSun : NoshiSymbolMoon, NoshiSymbolPerson, NoshiSymbolMegaphone, NoshiSymbolBookmark, NoshiSymbolStar, NoshiSymbolLock};
    NSUInteger proxyIndex = NSNotFound;
    if (proxyEnabled) {
        proxyIndex = titles.count;
        [titles addObject:NSLocalizedString(@"proxy.title", nil)];
    }
    /* the card's handler holds this object, which the screen that made it does not keep */
    [self retain];
    NoshiPopupMenu *menu = [[[NoshiPopupMenu alloc] initWithTitles:titles symbols:symbols handler:^(NSUInteger index) {
        if (index == proxyIndex) [self openProxyList];
        else switch (index) {
        case 0: [self toggleDayNight]; break;
        case 1: [self askNameForMegagroup:YES]; break;
        case 2: [self askNameForMegagroup:NO]; break;
        case 3: [self openSavedMessages]; break;
        default: [self openBookmarks]; break;
        }
        [self autorelease];
    }] autorelease];
    [menu showInView:view anchor:anchor];
}

/* the proxies are kept on the More page of the settings, with the switch and the link prompt */
- (void)openProxyList {
    [_host.navigationController pushViewController:[[[NoshiMoreSettingsController alloc] initWithSession:_session] autorelease] animated:YES];
}

- (void)openBookmarks {
    [_host.navigationController pushViewController:[[[NoshiBookmarksController alloc] initWithSession:_session avatars:_avatars media:_media stickers:_stickers] autorelease] animated:YES];
}

- (void)toggleDayNight {
    NoshiThemeStoreDark(!NoshiThemeIsDark());
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil];
}

- (void)askNameForMegagroup:(BOOL)megagroup {
    Class alertClass = NoshiAlertClass();
    id alert = [[alertClass alloc] initWithTitle:NSLocalizedString(megagroup ? @"create.group.title" : @"create.channel.title", nil) message:nil delegate:self
                               cancelButtonTitle:NSLocalizedString(@"attach.cancel", nil) otherButtonTitles:NSLocalizedString(@"create.action", nil), nil];
    /* the plain text input style came with ios 5 */
    [alert setValue:[NSNumber numberWithInt:2] forKey:@"alertViewStyle"];
    [[alert textFieldAtIndex:0] setPlaceholder:NSLocalizedString(@"create.name", nil)];
    [alert setTag:megagroup ? 1 : 2];
    /* the alert keeps no reference to its delegate, so this object stays until its answer */
    [self retain];
    [alert show];
    [alert release];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self autorelease];
        return;
    }
    NSString *name = [[[alertView textFieldAtIndex:0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) {
        [self autorelease];
        return;
    }
    [_session createChannelTitled:name megagroup:alertView.tag == 1 completion:^(NSString *errorName) {
        if (errorName) [self showFailureText:[NSString stringWithFormat:NSLocalizedString(@"create.failed", nil), errorName]];
        else if (_refresh) _refresh();
        [self autorelease];
    }];
}

- (void)openSavedMessages {
    [self retain];
    [_session loadSelf:^(NSArray *items, NSString *errorName) {
        NoshiPerson *person = [items count] ? [items objectAtIndex:0] : nil;
        NoshiDialog *saved = person ? [NoshiDialog savedMessagesWithPerson:person] : nil;
        if (!saved) {
            [self showFailureText:[errorName isEqualToString:@"TIMEOUT"] ? NSLocalizedString(@"error.offline", nil)
                                                                         : [NSString stringWithFormat:NSLocalizedString(@"error.unknown", nil), errorName ? errorName : @"?"]];
            [self autorelease];
            return;
        }
        NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:saved avatars:_avatars media:_media stickers:_stickers] autorelease];
        chat.hidesBottomBarWhenPushed = YES;
        chat.closeHandler = ^{ if (_refresh) _refresh(); };
        [_host.navigationController pushViewController:chat animated:YES];
        [self autorelease];
    }];
}

@end

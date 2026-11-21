#import "noshi_platform.h"
#import "noshi_link_router.h"
#import "noshi_group_call_engine.h"

#import <QuartzCore/QuartzCore.h>

#import "noshi_alert.h"
#import "noshi_star_gift.h"
#import "noshi_browser_controller.h"
#import "noshi_browser_settings.h"
#import "noshi_chat_controller.h"
#import "noshi_session_channels.h"
#import "noshi_dialog_picker_controller.h"
#import "noshi_gift_screen.h"
#import "noshi_invite_sheet.h"
#import "noshi_language.h"
#import "noshi_language_controller.h"
#import "noshi_language_pack.h"
#import "noshi_session_language.h"
#import "noshi_session_theme.h"
#import "noshi_imported_theme.h"
#import "noshi_imported_theme_preview_controller.h"
#import "noshi_translate_config.h"
#import "noshi_theme.h"
#import "noshi_proxy_settings.h"
#import "noshi_rewind.h"
#import "noshi_user_profile_controller.h"

#include "noshi_links.h"
#include "noshi_tgios_theme.h"
#include "noshi_bytes.h"

/* the schemes an address in a message or a button may hand to the system; javascript:, file: and the rest are not links to follow */
static BOOL NoshiSystemSchemeAllowed(NSString *scheme) {
    NSString *lower = scheme.lowercaseString;
    return [lower isEqualToString:@"http"] || [lower isEqualToString:@"https"] || [lower isEqualToString:@"mailto"] || [lower isEqualToString:@"tel"];
}

@interface NoshiBusyView : UIView {
    UIActivityIndicatorView *_spinner;
}
+ (void)showFor:(NSUInteger)token;
+ (void)hideFor:(NSUInteger)token;
@end

static NoshiBusyView *sBusy = nil;
static NSUInteger sBusyToken = 0;

@implementation NoshiBusyView

- (id)init {
    self = [super initWithFrame:CGRectMake(0, 0, 80, 80)];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    self.layer.cornerRadius = 12;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.center = CGPointMake(40, 40);
    [self addSubview:_spinner];
    [_spinner startAnimating];
    return self;
}

- (void)dealloc {
    [_spinner release];
    [super dealloc];
}

+ (void)showFor:(NSUInteger)token {
    UIView *window = NoshiOverlayHost();
    if (!window) return;
    sBusyToken = token;
    if (!sBusy) sBusy = [[NoshiBusyView alloc] init];
    sBusy.center = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
    sBusy.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [window addSubview:sBusy];
}

/* only the call that put the spinner up takes it down, so a late answer of an earlier tap does not hide the spinner of a later one */
+ (void)hideFor:(NSUInteger)token {
    if (token != sBusyToken) return;
    [sBusy removeFromSuperview];
}

@end

@implementation NoshiLinkRouter

@synthesize anchor = _anchor;
@synthesize session = _session;

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
             stickers:(NoshiStickerLibrary *)stickers {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _stickers = [stickers retain];
    return self;
}

- (void)dealloc {
    [_session release];
    [_avatars release];
    [_media release];
    [_stickers release];
    [super dealloc];
}

+ (NSString *)textForError:(NSString *)errorName {
    if ([errorName isEqualToString:@"TIMEOUT"]) return NSLocalizedString(@"error.offline", nil);
    if ([errorName isEqualToString:@"USERNAME_NOT_FOUND"]) return NSLocalizedString(@"bots.error.username", nil);
    if ([errorName isEqualToString:@"BOT_RESPONSE_TIMEOUT"]) return NSLocalizedString(@"bots.error.timeout", nil);
    if ([errorName isEqualToString:@"PASSWORD_HASH_INVALID"]) return NSLocalizedString(@"bots.error.password", nil);
    if ([errorName isEqualToString:@"BOT_APP_INVALID"] || [errorName isEqualToString:@"BOT_INVALID"]) return NSLocalizedString(@"bots.error.app", nil);
    if ([errorName isEqualToString:@"BOT_DOMAIN_INVALID"] || [errorName isEqualToString:@"URL_INVALID"]) return NSLocalizedString(@"bots.error.domain", nil);
    if ([errorName isEqualToString:@"STARS_UNSUPPORTED"] || [errorName isEqualToString:@"BOT_PRECHECKOUT_FAILED"]) return NSLocalizedString(@"gifts.error.unsupported", nil);
    if ([errorName isEqualToString:@"BALANCE_TOO_LOW"] || [errorName isEqualToString:@"BALANCE_LOW"]) return NSLocalizedString(@"gifts.error.balance", nil);
    if ([errorName isEqualToString:@"INVITE_HASH_EXPIRED"] || [errorName isEqualToString:@"INVITE_HASH_INVALID"] || [errorName isEqualToString:@"INVITE_HASH_EMPTY"]) return NSLocalizedString(@"invite.error.expired", nil);
    if ([errorName isEqualToString:@"INVITE_REQUEST_SENT"]) return NSLocalizedString(@"invite.error.sent", nil);
    if ([errorName isEqualToString:@"USER_ALREADY_PARTICIPANT"]) return NSLocalizedString(@"invite.error.member", nil);
    if ([errorName isEqualToString:@"USERS_TOO_MUCH"] || [errorName isEqualToString:@"CHANNELS_TOO_MUCH"]) return NSLocalizedString(@"invite.error.full", nil);
    if ([errorName isEqualToString:@"JOIN_WEBVIEW"]) return NSLocalizedString(@"invite.error.webview", nil);
    if ([errorName isEqualToString:@"INTERNAL"]) return NSLocalizedString(@"error.internal", nil);
    if ([errorName isEqualToString:@"CHANNEL_PRIVATE"] || [errorName isEqualToString:@"CHANNEL_INVALID"]) return NSLocalizedString(@"link.error.private", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"bots.error.unknown", nil), errorName ? errorName : @"?"];
}

- (NSUInteger)beginBusy {
    ++_token;
    [NoshiBusyView showFor:_token];
    return _token;
}

- (void)endBusy:(NSUInteger)token {
    [NoshiBusyView hideFor:token];
}

- (void)showNote:(NSString *)text {
    if (!text.length) return;
    UIView *window = NoshiOverlayHost();
    if (!window) return;
    UILabel *label = [[[UILabel alloc] init] autorelease];
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
    label.textColor = [UIColor whiteColor];
    label.font = NoshiFontMedium(15);
    label.textAlignment = NoshiTextAlignmentCenter;
    label.numberOfLines = 3;
    label.text = text;
    label.layer.cornerRadius = 10;
    label.clipsToBounds = YES;
    CGFloat width = MIN(window.bounds.size.width - 48, 340);
    CGSize fit = [label sizeThatFits:CGSizeMake(width - 24, 200)];
    label.frame = CGRectMake(0, 0, MIN(width, fit.width + 28), fit.height + 18);
    label.center = CGPointMake(CGRectGetMidX(window.bounds), window.bounds.size.height - 110 - label.frame.size.height / 2);
    label.alpha = 0;
    [window addSubview:label];
    [UIView animateWithDuration:0.2 animations:^{ label.alpha = 1; } completion:^(BOOL done) {
        (void)done;
        [UIView animateWithDuration:0.3 delay:2.2 options:0 animations:^{ label.alpha = 0; } completion:^(BOOL finished) {
            (void)finished;
            [label removeFromSuperview];
        }];
    }];
}

NSString *const NoshiOpenLinkNotification = @"NoshiOpenLink";

BOOL NoshiIsTelegramLink(NSURL *url) {
    NSString *scheme = [url.scheme lowercaseString];
    if ([scheme isEqualToString:@"tg"]) return YES;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;
    NSString *host = [url.host lowercaseString];
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    return [host isEqualToString:@"t.me"] || [host isEqualToString:@"telegram.me"] || [host isEqualToString:@"telegram.dog"];
}

- (UINavigationController *)navigation {
    return _anchor.navigationController;
}

- (void)openExternal:(NSString *)url {
    NSURL *target = [NSURL URLWithString:url];
    if (!target || !NoshiSystemSchemeAllowed(target.scheme)) {
        [self showNote:NSLocalizedString(@"bots.error.link", nil)];
        return;
    }
    if (![[UIApplication sharedApplication] openURL:target]) [self showNote:NSLocalizedString(@"bots.error.link", nil)];
}

#pragma mark language packs

/* the window of a t.me/setlanguage link, worded as the one of Telegram. the server describes the pack, but the texts of this app are in its own bundle, so
   a pack is applied only for a language the bundle has, and the share it shows is the share of the app's texts that language translates */
- (void)showLanguagePack:(NoshiLanguagePack *)pack {
    NSString *target = NoshiInterfaceLanguageForPackCode(pack.code);
    if (target && [NoshiNormalizedLanguageCode(NoshiInterfaceLanguageVariant()) isEqualToString:NoshiNormalizedLanguageCode(target)]) {
        NoshiShowAlert(NSLocalizedString(@"language.title", nil), [NSString stringWithFormat:NSLocalizedString(@"language.link.same", nil), pack.name],
                         [NSArray arrayWithObjects:NSLocalizedString(@"notice.ok", nil), NSLocalizedString(@"tab.settings", nil), nil], 0, NO,
                         ^(NSInteger index, NSString *text) {
            (void)text;
            if (index != 1) return;
            UINavigationController *navigation = [self navigation];
            if (navigation) [navigation pushViewController:[[[NoshiLanguageSettingsController alloc] init] autorelease] animated:YES];
        });
        return;
    }
    if (!target) {
        NoshiShowNotice(NSLocalizedString(@"language.link.nodata.title", nil),
                          [NSString stringWithFormat:NSLocalizedString(pack.official ? @"language.link.nodata" : @"language.link.nodata.custom", nil), pack.name]);
        return;
    }
    NSString *message = [NSString stringWithFormat:NSLocalizedString(pack.official ? @"language.link.alert" : @"language.link.alert.custom", nil), pack.name,
                         NoshiInterfaceLanguageCompleteness(target)];
    NoshiConfirm(NSLocalizedString(@"language.link.title", nil), message, NSLocalizedString(@"language.link.change", nil), ^{
        NSString *previous = NoshiInterfaceLanguage();
        NoshiSetInterfaceLanguage(target);
        NoshiTranslateInterfaceLanguageChanged(previous, NoshiInterfaceLanguage());
    });
}

- (void)openLanguageOfCode:(NSString *)code {
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session loadLanguagePack:code completion:^(NoshiLanguagePack *pack, NSString *errorName) {
        [self endBusy:token];
        [self autorelease];
        if (pack) {
            [self showLanguagePack:pack];
            return;
        }
        BOOL unknown = [errorName isEqualToString:@"LANG_CODE_NOT_SUPPORTED"] || [errorName isEqualToString:@"LANG_PACK_INVALID"] || [errorName isEqualToString:@"LANG_CODE_INVALID"];
        NoshiShowNotice(NSLocalizedString(@"language.title", nil), unknown ? NSLocalizedString(@"language.link.unsupported", nil) : [NoshiLinkRouter textForError:errorName]);
    }];
}

#pragma mark themes

/* the preview reads its theme from disk and the apply reads it again, so the file stays under one fixed name that the next link replaces */
static NSString *NoshiCloudThemePath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"noshigram-cloud-theme.tgios-theme"];
}

/* the accent goes to the color of one's own that the app keeps (hue, saturation and a brightness against the accent of the palette, whose value is 0.745), and the base look
   to the dark or light palette; the rest of a theme made elsewhere (message colors, wallpaper) has no place here */
- (void)offerColorsOfTheme:(NoshiThemeLink *)theme {
    BOOL dark = theme.dark;
    uint32_t accent = theme.accent;
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"theme.link.colors", nil), theme.title];
    NoshiShowAlert(NSLocalizedString(@"theme.import.title", nil), message,
                     [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"theme.link.apply", nil), nil], 0, NO,
                     ^(NSInteger index, NSString *text) {
        (void)text;
        if (index != 1) return;
        CGFloat hue, saturation, value;
        NoshiRGBToHSV(((accent >> 16) & 0xFF) / 255.0, ((accent >> 8) & 0xFF) / 255.0, (accent & 0xFF) / 255.0, &hue, &saturation, &value);
        NoshiImportedThemeUseBuiltin(dark);
        NoshiThemeStoreDark(dark);
        NoshiThemeStoreCustomTint((float)hue, (float)saturation, (float)MIN(1, value / 0.745));
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil];
    });
}

- (void)openThemeOfSlug:(NSString *)slug {
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session loadThemeOfSlug:slug completion:^(NoshiThemeLink *theme, NSString *errorName) {
        if (!theme) {
            BOOL unknown = [errorName isEqualToString:@"THEME_SLUG_INVALID"] || [errorName isEqualToString:@"THEME_FORMAT_INVALID"];
            [self endBusy:token];
            NoshiShowNotice(NSLocalizedString(@"theme.import.title", nil), unknown ? NSLocalizedString(@"theme.link.notfound", nil) : [NoshiLinkRouter textForError:errorName]);
            [self autorelease];
            return;
        }
        /* a theme made in another app has no .tgios-theme, and the server sends only its colors: the base look and the accent */
        if (!theme.file) {
            [self endBusy:token];
            if (theme.hasColors) [self offerColorsOfTheme:theme];
            else NoshiShowNotice(NSLocalizedString(@"theme.import.title", nil), NSLocalizedString(@"theme.link.unsupported", nil));
            [self autorelease];
            return;
        }
        if (theme.file.size <= 0 || theme.file.size > (long long)NOSHI_TGIOS_MAX_BYTES) {
            [self endBusy:token];
            NoshiShowNotice(NSLocalizedString(@"theme.import.title", nil), NSLocalizedString(@"theme.import.size", nil));
            [self autorelease];
            return;
        }
        [_media loadDataForFile:theme.file.file completion:^(NSData *data) {
            [self endBusy:token];
            NSString *path = NoshiCloudThemePath();
            NSError *writeError = nil;
            if (!data.length) {
                NoshiShowNotice(NSLocalizedString(@"theme.import.title", nil), NSLocalizedString(@"theme.link.download", nil));
            } else if (![data writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
                NSLog(@"noshigram: cloud theme did not save: %@", writeError);
                NoshiShowNotice(NSLocalizedString(@"theme.import.title", nil), NSLocalizedString(@"theme.import.save", nil));
            } else if (_anchor) {
                [NoshiImportedThemePreviewController openURL:[NSURL fileURLWithPath:path] fromController:_anchor];
            }
            [self autorelease];
        }];
    }];
}

#pragma mark links

- (void)openLink:(NSString *)url {
    if (!url.length) return;
    NSURL *webURL = [NSURL URLWithString:url];
    if (NoshiIsWebURL(webURL) && !NoshiIsTelegramLink(webURL)) {
        if (NoshiRewindOpenLink(webURL)) return;
        NSString *choice = NoshiBrowserChoice();
        if ([choice isEqualToString:@"noshigram"]) NoshiPresentBrowser(webURL, _anchor);
        else if (!NoshiBrowserOpenExternal(webURL, choice)) [self showNote:NSLocalizedString(@"browser.settings.open.failed", nil)];
        return;
    }
    static NSString *const mentionPrefix = @"noshigram-mention:";
    if ([url hasPrefix:mentionPrefix]) {
        [self openMention:[url substringFromIndex:mentionPrefix.length]];
        return;
    }
    noshi_tg_link link;
    if (noshi_tg_link_parse(url.UTF8String, &link) != NOSHI_OK) {
        [self showNote:NSLocalizedString(@"bots.error.link", nil)];
        return;
    }
    switch (link.kind) {
    case NOSHI_LINK_OTHER:
        [self openExternal:url];
        return;
    case NOSHI_LINK_INVOICE: {
        [self payInvoiceOfSlug:[NSString stringWithUTF8String:link.slug] completion:nil];
        return;
    }
    case NOSHI_LINK_INVITE:
        [self openInviteOfHash:[NSString stringWithUTF8String:link.slug]];
        return;
    case NOSHI_LINK_PROXY:
    case NOSHI_LINK_SOCKS: {
        noshi_proxy proxy;
        noshi_status status = noshi_proxy_from_link(&link, &proxy);
        if (status != NOSHI_OK) {
            noshi_wipe(&proxy, sizeof(proxy));
            noshi_wipe(&link, sizeof(link));
            NoshiShowNotice(NSLocalizedString(@"proxy.title", nil), NSLocalizedString(@"proxy.invalid", nil));
            return;
        }
        NSString *description = [NSString stringWithFormat:NSLocalizedString(@"proxy.confirm", nil),
            proxy.kind == NOSHI_PROXY_SOCKS5 ? @"SOCKS5" : @"MTProto", proxy.server, (unsigned)proxy.port];
        noshi_wipe(&proxy, sizeof(proxy));
        noshi_wipe(&link, sizeof(link));
        NoshiConfirm(NSLocalizedString(@"proxy.title", nil), description, NSLocalizedString(@"proxy.enable", nil), ^{
            noshi_status saved = NoshiProxyStoreLink(url);
            if (saved != NOSHI_OK) NoshiShowNotice(NSLocalizedString(@"proxy.title", nil), NSLocalizedString(@"proxy.savefailed", nil));
        });
        return;
    }
    case NOSHI_LINK_LANGUAGE:
        [self openLanguageOfCode:[NSString stringWithUTF8String:link.slug]];
        return;
    case NOSHI_LINK_THEME:
        [self openThemeOfSlug:[NSString stringWithUTF8String:link.slug]];
        return;
    case NOSHI_LINK_CALL:
        /* a conference call is end-to-end encrypted with a protocol this app does not have, so its link is told apart from a person's */
        NoshiShowNotice(NSLocalizedString(@"group.title", nil), NSLocalizedString(@"group.notice.unsupported", nil));
        return;
    case NOSHI_LINK_PRIVATE_POST: {
        long long channelId = link.channel_id;
        int32_t messageId = link.message_id;
        NSUInteger token = [self beginBusy];
        [self retain];
        [_session loadChannelDialogWithId:channelId completion:^(NoshiDialog *dialog, NSString *errorName) {
            [self endBusy:token];
            [self autorelease];
            if (!dialog) {
                [self showNote:[NoshiLinkRouter textForError:errorName]];
                return;
            }
            [self openDialog:dialog person:nil draft:nil startParam:nil messageId:messageId];
        }];
        return;
    }
    case NOSHI_LINK_PEER:
        break;
    }
    NSString *name = [NSString stringWithUTF8String:link.username];
    NSString *start = link.has_start && link.start[0] ? [NSString stringWithUTF8String:link.start] : nil;
    int32_t messageId = link.message_id;
    BOOL wantsVoiceChat = link.has_voice_chat != 0;
    NSString *voiceHash = link.voice_chat[0] ? [NSString stringWithUTF8String:link.voice_chat] : nil;
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session resolveUsername:name completion:^(NoshiDialog *resolved, NoshiPerson *person, NSString *errorName) {
        [self endBusy:token];
        [self autorelease];
        if (!resolved) {
            [self showNote:[NoshiLinkRouter textForError:errorName]];
            return;
        }
        [self openDialog:resolved person:person draft:nil startParam:person.bot ? start : nil messageId:messageId];
        /* ?videochat= names the voice chat of a group or channel: the chat opens behind it, and the call joins with the invite hash of the link */
        if (wantsVoiceChat && (resolved.peerKind == 2 || resolved.peerKind == 3)) [_session.groupCalls joinVoiceChatOfDialog:resolved inviteHash:voiceHash];
    }];
}

/* t.me/+hash: the chat opens when the account is in it already, and otherwise the person sees what it is and decides to join */
- (void)openInviteOfHash:(NSString *)hash {
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session checkInviteHash:hash completion:^(NoshiDialog *member, NSString *title, NSString *about, NoshiRemoteFile *photo, NSInteger participants, BOOL broadcast, BOOL requestNeeded, long long subscriptionStars, NSString *errorName) {
        [self endBusy:token];
        if (errorName) {
            [self showNote:[NoshiLinkRouter textForError:errorName]];
            [self autorelease];
            return;
        }
        if (member) {
            [self openDialog:member person:nil draft:nil startParam:nil messageId:0];
            [self autorelease];
            return;
        }
        NSString *kind = NSLocalizedString(broadcast ? @"invite.channel" : @"invite.group", nil);
        NSString *subtitle = [NSString stringWithFormat:NSLocalizedString(@"invite.members", nil), kind, (long)participants];
        [NoshiInviteSheet showInView:NoshiOverlayHost() title:title subtitle:subtitle about:about photo:photo media:_media requestNeeded:requestNeeded
                                joinTitle:subscriptionStars > 0 ? [NSString stringWithFormat:NSLocalizedString(@"invite.subscribe", nil), subscriptionStars] : nil
                                     join:^{
            if (subscriptionStars > 0) [self subscribeInviteOfHash:hash];
            else [self joinInviteOfHash:hash];
        }];
        [self autorelease];
    }];
}

/* a paid channel: the server quotes the price, the person agrees, the stars go, and the invite is read again, which now names the chat the account is in */
- (void)subscribeInviteOfHash:(NSString *)hash {
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session quoteSubscribingInviteHash:hash completion:^(NoshiPaymentQuote *quote, NSString *errorName) {
        [self endBusy:token];
        if (!quote) {
            [self showNote:[NoshiLinkRouter textForError:errorName]];
            [self autorelease];
            return;
        }
        NoshiShowAlert(nil, [NSString stringWithFormat:NSLocalizedString(@"invite.subscribe.confirm", nil), quote.stars],
                         [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil), NSLocalizedString(@"invite.subscribe.button", nil), nil], 0, NO,
                         ^(NSInteger index, NSString *text) {
            (void)text;
            if (index != 1) {
                [self autorelease];
                return;
            }
            NSUInteger payToken = [self beginBusy];
            [_session payQuote:quote completion:^(NSString *payError) {
                if (payError) {
                    [self endBusy:payToken];
                    [self showNote:[NoshiLinkRouter textForError:payError]];
                    [self autorelease];
                    return;
                }
                [_session checkInviteHash:hash completion:^(NoshiDialog *member, NSString *title, NSString *about, NoshiRemoteFile *photo, NSInteger participants,
                                                            BOOL broadcast, BOOL requestNeeded, long long stars, NSString *checkError) {
                    [self endBusy:payToken];
                    [self autorelease];
                    if (!member) {
                        NSLog(@"noshigram: the subscription was paid but the chat did not open: %@", checkError ? checkError : @"not a member yet");
                        [self showNote:[NoshiLinkRouter textForError:checkError ? checkError : @"INTERNAL"]];
                        return;
                    }
                    [self openDialog:member person:nil draft:nil startParam:nil messageId:0];
                }];
            }];
        });
    }];
}

- (void)joinInviteOfHash:(NSString *)hash {
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session joinInviteHash:hash completion:^(NoshiDialog *dialog, NSString *errorName) {
        [self endBusy:token];
        [self autorelease];
        if (!dialog) {
            [self showNote:[NoshiLinkRouter textForError:errorName]];
            return;
        }
        [self openDialog:dialog person:nil draft:nil startParam:nil messageId:0];
    }];
}

/* a @name in a message: a person opens their profile, a group or channel opens its chat */
- (void)openMention:(NSString *)name {
    char buffer[NOSHI_LINK_NAME_MAX];
    if (noshi_mention_name(name.UTF8String, buffer, sizeof(buffer)) != NOSHI_OK) {
        [self showNote:NSLocalizedString(@"bots.error.link", nil)];
        return;
    }
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session resolveUsername:name completion:^(NoshiDialog *resolved, NoshiPerson *person, NSString *errorName) {
        [self endBusy:token];
        [self autorelease];
        if (!resolved) {
            [self showNote:[NoshiLinkRouter textForError:errorName]];
            return;
        }
        UINavigationController *navigation = [self navigation];
        if (!person || !navigation) {
            [self openDialog:resolved person:person draft:nil startParam:nil messageId:0];
            return;
        }
        /* a user the server names without an access hash (the account itself) has no dialog made from the person, and a profile built on nil has no peer to ask for */
        NoshiDialog *peer = [NoshiDialog dialogWithPerson:person];
        NoshiUserProfileController *profile = [[[NoshiUserProfileController alloc] initWithSession:_session dialog:peer ? peer : resolved avatars:_avatars
                                                                                                  media:_media stickers:_stickers] autorelease];
        [navigation pushViewController:profile animated:YES];
    }];
}

#pragma mark screens

- (void)openDialog:(NoshiDialog *)dialog person:(NoshiPerson *)person draft:(NSString *)draft startParam:(NSString *)startParam {
    [self openDialog:dialog person:person draft:draft startParam:startParam messageId:0];
}

- (void)openDialog:(NoshiDialog *)dialog person:(NoshiPerson *)person draft:(NSString *)draft startParam:(NSString *)startParam messageId:(int32_t)messageId {
    (void)person;
    UINavigationController *navigation = [self navigation];
    if (!navigation) return;
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:_session dialog:dialog avatars:_avatars media:_media
                                                                          stickers:_stickers] autorelease];
    chat.draftText = draft;
    chat.startParam = startParam;
    chat.startMessageId = messageId;
    [navigation pushViewController:chat animated:YES];
}

- (void)openProfileOfUser:(long long)userId inMessage:(int32_t)messageId dialog:(NoshiDialog *)dialog {
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session loadUser:userId ofMessage:messageId inDialog:dialog completion:^(NoshiPerson *person, NSString *errorName) {
        [self endBusy:token];
        [self autorelease];
        NoshiDialog *chat = person ? [NoshiDialog dialogWithPerson:person] : nil;
        UINavigationController *navigation = [self navigation];
        if (!chat || !navigation) {
            if (!person) [self showNote:[NoshiLinkRouter textForError:errorName]];
            return;
        }
        NoshiUserProfileController *profile = [[[NoshiUserProfileController alloc] initWithSession:_session dialog:chat avatars:_avatars media:_media
                                                                                               stickers:_stickers] autorelease];
        [navigation pushViewController:profile animated:YES];
    }];
}

- (void)pickDialogsWithFilter:(BOOL (^)(NoshiDialog *))filter limit:(NSUInteger)limit completion:(void (^)(NSArray *))completion cancelled:(void (^)(void))cancelled {
    UINavigationController *navigation = [self navigation];
    if (!navigation) {
        /* later, not here: the caller may be a plugin service still waiting for this call to return */
        if (cancelled) {
            void (^later)(void) = [cancelled copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                later();
                [later release];
            });
        }
        return;
    }
    NoshiDialogPickerController *picker = [[[NoshiDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"bots.pick.title", nil);
    picker.filter = filter;
    picker.limit = limit;
    picker.pickHandler = completion;
    picker.cancelHandler = cancelled;
    [navigation pushViewController:picker animated:YES];
}

- (void)pickDialogWithTypes:(uint8_t)types completion:(void (^)(NoshiDialog *))completion {
    UINavigationController *navigation = [self navigation];
    if (!navigation) return;
    void (^done)(NoshiDialog *) = [completion copy];
    NoshiDialogPickerController *picker = [[[NoshiDialogPickerController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
    picker.screenTitle = NSLocalizedString(@"bots.pick.title", nil);
    picker.filter = ^BOOL(NoshiDialog *dialog) {
        if (!types) return YES;
        switch (dialog.kind) {
        case NOSHI_DIALOG_USER: return (types & 1u) != 0;
        case NOSHI_DIALOG_BOT: return (types & 2u) != 0;
        case NOSHI_DIALOG_GROUP: return (types & 4u) != 0;
        case NOSHI_DIALOG_CHANNEL: return (types & 8u) != 0;
        }
        return NO;
    };
    picker.pickHandler = ^(NSArray *dialogs) {
        done([dialogs lastObject]);
        [done release];
    };
    [navigation pushViewController:picker animated:YES];
}

#pragma mark invoices

- (void)confirmInvoice:(NoshiStarsInvoice *)invoice completion:(void (^)(NSString *))completion {
    NSString *message = invoice->invoiceDescription.length
        ? [NSString stringWithFormat:@"%@\n\n%@", invoice->invoiceDescription, NoshiStarsText(invoice->stars)]
        : NoshiStarsText(invoice->stars);
    void (^done)(NSString *) = [completion copy];
    NoshiShowAlert(invoice->title.length ? invoice->title : NSLocalizedString(@"bots.invoice.title", nil), message,
                     [NSArray arrayWithObjects:NSLocalizedString(@"picker.cancel", nil),
                      [NSString stringWithFormat:NSLocalizedString(@"bots.invoice.pay", nil), NoshiStarsText(invoice->stars)], nil],
                     0, NO, ^(NSInteger index, NSString *text) {
        (void)text;
        if (index != 1) {
            if (done) done(@"cancelled");
            [done release];
            return;
        }
        NSUInteger token = [self beginBusy];
        [self retain];
        [_session payStarsInvoice:invoice completion:^(NSString *errorName) {
            [self endBusy:token];
            [self autorelease];
            if (errorName) [self showNote:[NoshiLinkRouter textForError:errorName]];
            if (done) done(errorName ? @"failed" : @"paid");
            [done release];
        }];
    });
}

- (void)handleInvoice:(NoshiStarsInvoice *)invoice error:(NSString *)errorName token:(NSUInteger)token completion:(void (^)(NSString *))done {
    [self endBusy:token];
    if (!invoice) {
        [self showNote:[NoshiLinkRouter textForError:errorName]];
        if (done) done(@"failed");
        [done release];
        return;
    }
    [self confirmInvoice:invoice completion:done];
    [done release];
}

- (void)payInvoiceOfSlug:(NSString *)slug completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session loadStarsInvoiceOfSlug:slug completion:^(NoshiStarsInvoice *invoice, NSString *errorName) {
        [self autorelease];
        [self handleInvoice:invoice error:errorName token:token completion:[done retain]];
        [done release];
    }];
}

- (void)payInvoiceOfMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *))completion {
    void (^done)(NSString *) = [completion copy];
    NSUInteger token = [self beginBusy];
    [self retain];
    [_session loadStarsInvoiceOfMessage:messageId inDialog:dialog completion:^(NoshiStarsInvoice *invoice, NSString *errorName) {
        [self autorelease];
        [self handleInvoice:invoice error:errorName token:token completion:[done retain]];
        [done release];
    }];
}

@end

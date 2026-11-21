#import "noshi_more_settings_controller.h"

#import "noshi_alert.h"
#import "noshi_chat_settings.h"
#import "noshi_gift_screen.h"
#import "noshi_problem_report.h"
#import "noshi_proxy_settings.h"
#import "noshi_session_data.h"
#import "noshi_settings_reset.h"
#import "noshi_sheet.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"
#include "noshi_bytes.h"

@interface NoshiMoreSettingsController () {
    NoshiSession *_session;
    NoshiWeakReference *_weak;
    BOOL _deleting;
}
@end

@implementation NoshiMoreSettingsController

- (id)initWithSession:(NoshiSession *)session {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"about.more", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiMoreSettingsController alloc] initWithSession:_session] autorelease];
}

/* the screens read these settings when they are built, so the main controller builds them again, from the row that was touched */
- (void)apply {
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil
                                                      userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:self.selectPoint] forKey:NoshiThemeOriginKey]];
}

#pragma mark deleting the account

/* two questions, the second asking for the word, since nothing brings the account back */
- (void)askDeleteAccount {
    if (_deleting) return;
    NoshiWeakReference *weak = _weak;
    NoshiConfirmAction(self, NSLocalizedString(@"more.delete.confirm", nil), NSLocalizedString(@"more.delete.action", nil), ^{
        NoshiPromptText(NSLocalizedString(@"more.delete.title", nil), [NSString stringWithFormat:NSLocalizedString(@"more.delete.type", nil), NSLocalizedString(@"more.delete.word", nil)], nil, nil, ^(NSString *text) {
            NoshiMoreSettingsController *me = weak.target;
            if (!me) return;
            NSString *typed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([typed caseInsensitiveCompare:NSLocalizedString(@"more.delete.word", nil)] != NSOrderedSame) {
                NoshiGiftAlert(nil, NSLocalizedString(@"more.delete.mismatch", nil));
                return;
            }
            [me deleteAccountNow];
        });
    });
}

static NSString *NoshiDeleteErrorText(NSString *errorName) {
    /* an account with a cloud password has to wait for the deletion; the wait starts with the first try */
    if ([errorName hasPrefix:@"2FA_CONFIRM_WAIT"]) return NSLocalizedString(@"more.delete.wait", nil);
    if ([errorName hasPrefix:@"2FA_RECENT_CONFIRM"]) return NSLocalizedString(@"more.delete.recent", nil);
    return NoshiGiftErrorText(errorName);
}

- (void)deleteAccountNow {
    _deleting = YES;
    NoshiWeakReference *weak = _weak;
    [_session deleteAccountWithReason:@"Deleted from Noshigram" completion:^(NSString *errorName) {
        NoshiMoreSettingsController *me = weak.target;
        if (!me) return;
        me->_deleting = NO;
        if (errorName) {
            NoshiGiftAlert(nil, NoshiDeleteErrorText(errorName));
            return;
        }
        /* the server dropped the account, and the connection tells the app, which goes to the next account or to the welcome screen */
        NoshiGiftAlert(nil, NSLocalizedString(@"more.delete.done", nil));
    }];
}

#pragma mark rows

- (NoshiSettingsRow *)flagRow:(NSString *)titleKey info:(NSString *)infoKey flag:(NoshiChatFlag)flag rebuild:(BOOL)rebuild {
    NoshiWeakReference *weak = _weak;
    return [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(titleKey, nil) subtitle:infoKey ? NSLocalizedString(infoKey, nil) : nil on:NoshiChatFlagGet(flag)
                                           toggle:^(BOOL on) {
        NoshiChatFlagSet(flag, on);
        if (rebuild) [(NoshiMoreSettingsController *)weak.target apply];
    }];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    NoshiSettingsRow *reports = [self flagRow:@"more.reports" info:nil flag:NoshiChatFlagCrashReports rebuild:NO];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"more.reports.header", nil)
                                                           footer:nil
                                                             rows:[NSArray arrayWithObject:reports]]];

    noshi_proxy proxy;
    BOOL proxyEnabled = NO;
    noshi_status proxyStatus = NoshiProxyRead(&proxy, &proxyEnabled);
    noshi_wipe(&proxy, sizeof(proxy));
    NoshiSettingsRow *proxyToggle = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"proxy.current", nil)
        subtitle:NoshiProxyDisplay() on:proxyEnabled toggle:^(BOOL on) {
            noshi_status status = NoshiProxySetEnabled(on);
            if (status != NOSHI_OK) NoshiGiftAlert(nil, NSLocalizedString(status == NOSHI_E_NOTFOUND ? @"proxy.invalid" : @"proxy.savefailed", nil));
            [(NoshiMoreSettingsController *)weak.target rebuild];
        }];
    if (proxyStatus != NOSHI_OK) NSLog(@"noshigram: proxy settings unavailable: %s", noshi_status_name(proxyStatus));
    NoshiSettingsRow *proxyAdd = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"proxy.add", nil) value:nil tap:^{
        NoshiPromptText(NSLocalizedString(@"proxy.add", nil), nil, nil, NSLocalizedString(@"proxy.link.hint", nil), ^(NSString *text) {
            if (!text.length) return;
            noshi_status status = NoshiProxyStoreLink([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
            if (status != NOSHI_OK) NoshiGiftAlert(nil, NSLocalizedString(status == NOSHI_E_LIMIT ? @"proxy.limit" : status == NOSHI_E_STORAGE ? @"proxy.savefailed" : @"proxy.invalid", nil));
            [(NoshiMoreSettingsController *)weak.target rebuild];
        });
    }];
    NSMutableArray *proxyRows = [NSMutableArray arrayWithObject:proxyToggle];
    NSArray *savedProxies = nil;
    noshi_status listStatus = NoshiProxyList(&savedProxies);
    if (listStatus != NOSHI_OK) {
        NSLog(@"noshigram: saved proxies unavailable: %s", noshi_status_name(listStatus));
        [proxyRows addObject:[NoshiSettingsRow rowWithTitle:NSLocalizedString(@"proxy.savefailed", nil) value:nil tap:nil]];
    }
    for (NSUInteger i = 0; i < savedProxies.count; ++i) {
        NSDictionary *entry = [savedProxies objectAtIndex:i];
        NSString *address = [entry objectForKey:@"address"];
        BOOL selected = [[entry objectForKey:@"selected"] boolValue];
        [proxyRows addObject:[NoshiSettingsRow checkRowWithTitle:address subtitle:nil checked:selected tap:^{
            NoshiMoreSettingsController *page = weak.target;
            if (!page) return;
            NoshiSettingsChoose(page, address, [NSArray arrayWithObjects:NSLocalizedString(@"proxy.select", nil), NSLocalizedString(@"proxy.remove", nil), nil], ^(NSUInteger action) {
                noshi_status status = action == 0 ? NoshiProxySelect(i) : NoshiProxyRemove(i);
                if (status != NOSHI_OK) NoshiGiftAlert(nil, NSLocalizedString(@"proxy.savefailed", nil));
                [(NoshiMoreSettingsController *)weak.target rebuild];
            });
        }]];
    }
    [proxyRows addObject:proxyAdd];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"proxy.title", nil) footer:NSLocalizedString(@"proxy.info", nil) rows:proxyRows]];

    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"more.experimental", nil) footer:NSLocalizedString(@"more.localpremium.info", nil)
                                                             rows:[NSArray arrayWithObject:[self flagRow:@"more.localpremium" info:nil flag:NoshiChatFlagLocalPremium rebuild:YES]]]];

    NoshiSettingsRow *reset = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolRotate title:NSLocalizedString(@"more.reset", nil) destructive:YES tap:^{
        NoshiMoreSettingsController *me = weak.target;
        if (!me) return;
        NoshiConfirmAction(me, NSLocalizedString(@"more.reset.info", nil), NSLocalizedString(@"more.reset", nil), ^{
            NoshiResetSettings();
            [(NoshiMoreSettingsController *)weak.target apply];
        });
    }];
    NoshiSettingsRow *delete = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolTrash title:NSLocalizedString(@"more.delete", nil) destructive:YES tap:^{
        [(NoshiMoreSettingsController *)weak.target askDeleteAccount];
    }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"more.reset.footer", nil) rows:[NSArray arrayWithObjects:reset, delete, nil]]];

    self.sections = sections;
    [self reloadSettings];
}

@end

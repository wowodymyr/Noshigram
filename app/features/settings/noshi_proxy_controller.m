#import "noshi_proxy_controller.h"
#import "noshi_alert.h"
#import "noshi_gift_screen.h"
#import "noshi_proxy_settings.h"
#import "noshi_sheet.h"
#import "noshi_weak_reference.h"
#include "noshi_bytes.h"

@interface NoshiProxyController () {
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiProxyController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"proxy.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
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
    return [[[NoshiProxyController alloc] init] autorelease];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *sections = [NSMutableArray array];

    noshi_proxy proxy;
    BOOL proxyEnabled = NO;
    noshi_status proxyStatus = NoshiProxyRead(&proxy, &proxyEnabled);
    noshi_wipe(&proxy, sizeof(proxy));
    NoshiSettingsRow *proxyToggle = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"proxy.current", nil)
        subtitle:NoshiProxyDisplay() on:proxyEnabled toggle:^(BOOL on) {
            noshi_status status = NoshiProxySetEnabled(on);
            if (status != NOSHI_OK) NoshiGiftAlert(nil, NSLocalizedString(status == NOSHI_E_NOTFOUND ? @"proxy.invalid" : @"proxy.savefailed", nil));
            [(NoshiProxyController *)weak.target rebuild];
        }];
    if (proxyStatus != NOSHI_OK) NSLog(@"noshigram: proxy settings unavailable: %s", noshi_status_name(proxyStatus));
    NoshiSettingsRow *proxyAdd = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"proxy.add", nil) value:nil tap:^{
        NoshiPromptText(NSLocalizedString(@"proxy.add", nil), nil, nil, NSLocalizedString(@"proxy.link.hint", nil), ^(NSString *text) {
            if (!text.length) return;
            noshi_status status = NoshiProxyStoreLink([text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
            if (status != NOSHI_OK) NoshiGiftAlert(nil, NSLocalizedString(status == NOSHI_E_LIMIT ? @"proxy.limit" : status == NOSHI_E_STORAGE ? @"proxy.savefailed" : @"proxy.invalid", nil));
            [(NoshiProxyController *)weak.target rebuild];
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
            NoshiProxyController *page = weak.target;
            if (!page) return;
            NoshiSettingsChoose(page, address, [NSArray arrayWithObjects:NSLocalizedString(@"proxy.select", nil), NSLocalizedString(@"proxy.remove", nil), nil], ^(NSUInteger action) {
                noshi_status status = action == 0 ? NoshiProxySelect(i) : NoshiProxyRemove(i);
                if (status != NOSHI_OK) NoshiGiftAlert(nil, NSLocalizedString(@"proxy.savefailed", nil));
                [(NoshiProxyController *)weak.target rebuild];
            });
        }]];
    }
    [proxyRows addObject:proxyAdd];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"proxy.title", nil) footer:NSLocalizedString(@"proxy.info", nil) rows:proxyRows]];

    self.sections = sections;
    [self reloadSettings];
}

@end

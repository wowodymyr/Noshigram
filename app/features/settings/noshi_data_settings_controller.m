#import "noshi_data_settings_controller.h"

#import "noshi_draft.h"
#import "noshi_gift_screen.h"
#import "noshi_memory_controller.h"
#import "noshi_network_usage_controller.h"
#import "noshi_session_data.h"
#import "noshi_sheet.h"
#import "noshi_symbol.h"
#import "noshi_traffic_store.h"
#import "noshi_weak_reference.h"
#import "noshi_proxy_controller.h"

static NSString *NoshiDataSize(unsigned long long bytes) {
    if (!bytes) return nil;
    if (bytes >= 1024ull * 1024ull * 1024ull) return [NSString stringWithFormat:@"%.2f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
    if (bytes >= 1024ull * 1024ull) return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
}

@interface NoshiDataSettingsController () {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiWeakReference *_weak;
    BOOL _busy;
}
@end

@implementation NoshiDataSettingsController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media {
    self = [super init];
    if (!self) return nil;
    _session = [session retain];
    _avatars = [avatars retain];
    _media = [media retain];
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"settings.data", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [_session release];
    [_avatars release];
    [_media release];
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)themeDidChange {
    [self rebuild];
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiDataSettingsController alloc] initWithSession:_session avatars:_avatars media:_media] autorelease];
}

- (void)clearDrafts {
    if (_busy) return;
    _busy = YES;
    NoshiWeakReference *weak = _weak;
    [_session clearAllDraftsWithCompletion:^(NSString *errorName) {
        NoshiDataSettingsController *me = weak.target;
        if (!me) return;
        me->_busy = NO;
        if (errorName) {
            NoshiGiftAlert(nil, NoshiGiftErrorText(errorName));
            return;
        }
        [me->_session.drafts removeAll];
        NoshiGiftAlert(nil, NSLocalizedString(@"data.drafts.done", nil));
    }];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NoshiTrafficTotals totals = NoshiTrafficRead();
    unsigned long long network = totals.sent[0] + totals.sent[1] + totals.received[0] + totals.received[1];
    NoshiSettingsRow *memory = [NoshiSettingsRow rowWithSymbol:NoshiSymbolBroom tone:NoshiSettingsToneBlue title:NSLocalizedString(@"memory.title", nil) subtitle:nil
                                                             value:NoshiDataSize([_avatars diskBytes] + [_media diskBytes]) tap:^{
        NoshiDataSettingsController *me = weak.target;
        if (me) [me.navigationController pushViewController:[[[NoshiMemoryController alloc] initWithAvatars:me->_avatars media:me->_media] autorelease] animated:YES];
    }];
    NoshiSettingsRow *usage = [NoshiSettingsRow rowWithSymbol:NoshiSymbolGlobe tone:NoshiSettingsToneGreen title:NSLocalizedString(@"netusage.title", nil) subtitle:nil
                                                            value:NoshiDataSize(network) tap:^{
        [[(NoshiDataSettingsController *)weak.target navigationController] pushViewController:[[[NoshiNetworkUsageController alloc] init] autorelease] animated:YES];
    }];
    NoshiSettingsRow *drafts = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolTrash title:NSLocalizedString(@"data.drafts", nil) destructive:YES tap:^{
        NoshiDataSettingsController *me = weak.target;
        if (!me) return;
        NoshiConfirmAction(me, NSLocalizedString(@"data.drafts.confirm", nil), NSLocalizedString(@"data.drafts.action", nil), ^{ [(NoshiDataSettingsController *)weak.target clearDrafts]; });
    }];
    /* the proxy row of telegram 4.x */
    NoshiSettingsRow *proxyRow = [NoshiSettingsRow rowWithIconImage:[UIImage imageNamed:@"SettingsProxyIcon"] title:NSLocalizedString(@"proxy.title", nil) tap:^{
        [[(NoshiDataSettingsController *)weak.target navigationController] pushViewController:[[[NoshiProxyController alloc] init] autorelease] animated:YES];
    }];
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"data.usage", nil) footer:nil rows:[NSArray arrayWithObjects:memory, usage, nil]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:proxyRow]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"data.drafts.header", nil) footer:NSLocalizedString(@"data.drafts.info", nil) rows:[NSArray arrayWithObject:drafts]]];
    self.sections = sections;
    [self reloadSettings];
}

@end

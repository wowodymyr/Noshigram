#import "noshi_network_usage_controller.h"

#import "noshi_sheet.h"
#import "noshi_symbol.h"
#import "noshi_traffic_store.h"
#import "noshi_weak_reference.h"

/* "12.3 MB" the way the cache screen writes sizes, with kilobytes and bytes for the small ones */
static NSString *NoshiTrafficSize(unsigned long long bytes) {
    if (bytes >= 1024ull * 1024ull * 1024ull) return [NSString stringWithFormat:@"%.2f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
    if (bytes >= 1024ull * 1024ull) return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
    if (bytes >= 1024ull) return [NSString stringWithFormat:@"%.0f KB", (double)bytes / 1024.0];
    return [NSString stringWithFormat:@"%llu B", bytes];
}

@interface NoshiNetworkUsageController () {
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiNetworkUsageController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"netusage.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
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
    return [[[NoshiNetworkUsageController alloc] init] autorelease];
}

- (NoshiSettingsSection *)sectionNamed:(NSString *)header sent:(unsigned long long)sent received:(unsigned long long)received {
    NoshiSettingsRow *up = [NoshiSettingsRow rowWithSymbol:NoshiSymbolSendArrow tone:NoshiSettingsToneBlue title:NSLocalizedString(@"netusage.sent", nil) subtitle:nil
                                                         value:NoshiTrafficSize(sent) tap:nil];
    NoshiSettingsRow *down = [NoshiSettingsRow rowWithSymbol:NoshiSymbolArrowDown tone:NoshiSettingsToneGreen title:NSLocalizedString(@"netusage.received", nil) subtitle:nil
                                                           value:NoshiTrafficSize(received) tap:nil];
    NoshiSettingsRow *all = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"netusage.total", nil) value:NoshiTrafficSize(sent + received) tap:nil];
    return [NoshiSettingsSection sectionWithHeader:header footer:nil rows:[NSArray arrayWithObjects:up, down, all, nil]];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    NoshiTrafficTotals totals = NoshiTrafficRead();
    NSDateFormatter *format = [[[NSDateFormatter alloc] init] autorelease];
    format.dateStyle = NSDateFormatterMediumStyle;
    format.timeStyle = NSDateFormatterNoStyle;
    NSString *since = totals.since > 0 ? [NSString stringWithFormat:NSLocalizedString(@"netusage.since", nil), [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:totals.since]]] : nil;
    NoshiSettingsRow *reset = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolBroom title:NSLocalizedString(@"netusage.reset", nil) destructive:YES tap:^{
        NoshiNetworkUsageController *me = weak.target;
        if (!me) return;
        NoshiConfirmAction(me, NSLocalizedString(@"netusage.reset.confirm", nil), NSLocalizedString(@"netusage.reset", nil), ^{
            NoshiTrafficReset();
            [(NoshiNetworkUsageController *)weak.target rebuild];
        });
    }];
    NSMutableArray *sections = [NSMutableArray array];
    [sections addObject:[self sectionNamed:NSLocalizedString(@"netusage.wifi", nil) sent:totals.sent[0] received:totals.received[0]]];
    [sections addObject:[self sectionNamed:NSLocalizedString(@"netusage.cell", nil) sent:totals.sent[1] received:totals.received[1]]];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:since rows:[NSArray arrayWithObject:reset]]];
    self.sections = sections;
    [self reloadSettings];
}

@end

#import "noshi_time_zone_controller.h"

#import "noshi_time.h"
#import "noshi_weak_reference.h"

@interface NoshiTimeZoneController () {
    NoshiWeakReference *_weak;
    BOOL _positioned;
}
@end

@implementation NoshiTimeZoneController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"time.zone.title", nil);
    return self;
}

- (void)dealloc {
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)chooseOffset:(int32_t)minutes {
    NoshiTimeZoneSetChoice(minutes);
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    int32_t chosen = NoshiTimeZoneChoice();
    NoshiSettingsRow *automatic = [NoshiSettingsRow checkRowWithTitle:NSLocalizedString(@"time.zone.auto", nil) subtitle:nil
                                                                 checked:chosen == NOSHI_TIME_ZONE_AUTO tap:^{
        [(NoshiTimeZoneController *)weak.target chooseOffset:NOSHI_TIME_ZONE_AUTO];
    }];
    NSMutableArray *offsets = [NSMutableArray array];
    for (int32_t minutes = NOSHI_TIME_ZONE_MIN; minutes <= NOSHI_TIME_ZONE_MAX; minutes += NOSHI_TIME_ZONE_STEP) {
        [offsets addObject:[NoshiSettingsRow checkRowWithTitle:NoshiTimeZoneOffsetText(minutes) subtitle:nil checked:chosen == minutes tap:^{
            [(NoshiTimeZoneController *)weak.target chooseOffset:minutes];
        }]];
    }
    self.sections = [NSArray arrayWithObjects:
        [NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"time.zone.auto.info", nil) rows:[NSArray arrayWithObject:automatic]],
        [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"time.zone.manual", nil) footer:NSLocalizedString(@"time.zone.manual.info", nil) rows:offsets], nil];
    [self reloadSettings];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    int32_t chosen = NoshiTimeZoneChoice();
    if (!_positioned && chosen != NOSHI_TIME_ZONE_AUTO) {
        NSInteger row = (chosen - NOSHI_TIME_ZONE_MIN) / NOSHI_TIME_ZONE_STEP;
        [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
    _positioned = YES;
}

- (void)themeDidChange { [self rebuild]; }

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiTimeZoneController alloc] init] autorelease];
}

@end

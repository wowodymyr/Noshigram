#import "noshi_night_mode_controller.h"

#import "noshi_gift_screen.h"
#import "noshi_night_mode.h"
#import "noshi_symbol.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

/* the times the schedule can be set to: every half hour, the grid the default times (22:00 and 08:00) lie on */
#define TIME_STEP 30
#define TIMES_PER_DAY (24 * 60 / TIME_STEP)

@interface NoshiNightModeController () {
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiNightModeController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"chatset.night", nil);
    return self;
}

- (UIViewController *)controllerAfterThemeChange {
    return [[[NoshiNightModeController alloc] init] autorelease];
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

static NSString *NoshiClockText(int32_t minute) {
    return [NSString stringWithFormat:@"%02d:%02d", (int)(minute / 60), (int)(minute % 60)];
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    /* the sun times of today are worked out by a look at the decision, so a schedule by the sun shows what it will use */
    (void)NoshiNightDecision();
    noshi_night_config config = NoshiNightConfig();
    NSMutableArray *sections = [NSMutableArray array];

    NSMutableArray *titles = [NSMutableArray arrayWithObjects:NSLocalizedString(@"chatset.night.off", nil), NSLocalizedString(@"chatset.night.scheduled", nil),
                              NSLocalizedString(@"chatset.night.adaptive", nil), nil];
    if (NoshiNightSystemAvailable()) [titles addObject:NSLocalizedString(@"chatset.night.system", nil)];
    NSMutableArray *modes = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; ++i) {
        [modes addObject:[NoshiSettingsRow checkRowWithTitle:[titles objectAtIndex:i] subtitle:nil checked:(NSUInteger)config.mode == i tap:^{
            [(NoshiNightModeController *)weak.target chooseMode:(int32_t)i];
        }]];
    }
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"night.type.info", nil) rows:modes]];

    if (config.mode == NOSHI_NIGHT_SCHEDULED) {
        NoshiSettingsRow *sun = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"night.sun", nil) subtitle:nil on:config.by_sun != 0 toggle:^(BOOL on) {
            [(NoshiNightModeController *)weak.target setBySun:on];
        }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"night.schedule.header", nil) footer:nil rows:[NSArray arrayWithObject:sun]]];
    }
    if (config.mode == NOSHI_NIGHT_SCHEDULED && config.by_sun) {
        NSString *set = NoshiClockText(config.sunset_minute), *rise = NoshiClockText(config.sunrise_minute);
        NSString *info = config.sun_state == NOSHI_SUN_NEVER_RISES ? NSLocalizedString(@"night.sun.polarnight", nil)
                       : (config.sun_state == NOSHI_SUN_NEVER_SETS ? NSLocalizedString(@"night.sun.polarday", nil)
                                                                      : [NSString stringWithFormat:NSLocalizedString(@"night.sun.info", nil), set, rise]);
        NoshiSettingsRow *update = [NoshiSettingsRow actionRowWithSymbol:NoshiSymbolMapPin title:NSLocalizedString(@"night.sun.update", nil) destructive:NO tap:^{
            [(NoshiNightModeController *)weak.target updateLocation];
        }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:info rows:[NSArray arrayWithObject:update]]];
    } else if (config.mode == NOSHI_NIGHT_SCHEDULED) {
        NoshiSettingsRow *from = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"night.from", nil) value:NoshiClockText(config.from_minute) tap:^{
            [(NoshiNightModeController *)weak.target chooseTimeForStart:YES];
        }];
        NoshiSettingsRow *to = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"night.to", nil) value:NoshiClockText(config.to_minute) tap:^{
            [(NoshiNightModeController *)weak.target chooseTimeForStart:NO];
        }];
        NSString *info = [NSString stringWithFormat:NSLocalizedString(@"night.schedule.info", nil), NoshiClockText(config.from_minute), NoshiClockText(config.to_minute)];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:info rows:[NSArray arrayWithObjects:from, to, nil]]];
    } else if (config.mode == NOSHI_NIGHT_ADAPTIVE) {
        NoshiSettingsRow *slider = [NoshiSettingsRow sliderRowWithTitle:NSLocalizedString(@"night.brightness.row", nil) format:@"%.0f%%" value:(float)config.threshold_percent
                                                                    minimum:0 maximum:100 change:^(float value) {
            [(NoshiNightModeController *)weak.target thresholdMoved:value];
        }];
        NSString *info = [NSString stringWithFormat:NSLocalizedString(@"night.brightness.info", nil), (int)config.threshold_percent];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"night.brightness.header", nil) footer:info rows:[NSArray arrayWithObject:slider]]];
    }
    self.sections = sections;
    [self reloadSettings];
}

- (void)themeDidChange {
    [self rebuild];
}

/* a setup that turns the theme at this moment is applied as a switch of the settings is: the colors spread from the row that was touched, and this page
   stays, made again in the new colors */
- (void)applySetup {
    if (NoshiNightCheck(NO)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil
                                                          userInfo:[NSDictionary dictionaryWithObject:[NSValue valueWithCGPoint:self.selectPoint] forKey:NoshiThemeOriginKey]];
        return;
    }
    [self rebuild];
}

/* the place comes from the system, which asks the person the first time; a refusal leaves the schedule on its two times, and says why */
- (void)setBySun:(BOOL)on {
    noshi_night_config config = NoshiNightConfig();
    if (!on || NoshiNightHasLocation()) {
        config.by_sun = on ? 1 : 0;
        NoshiNightSetConfig(config);
        [self applySetup];
        return;
    }
    NoshiWeakReference *weak = _weak;
    NoshiNightRequestLocation(^(BOOL known) {
        NoshiNightModeController *me = weak.target;
        if (!me) return;
        if (!known) {
            NoshiGiftAlert(nil, NSLocalizedString(@"night.sun.denied", nil));
            [me rebuild];
            return;
        }
        noshi_night_config next = NoshiNightConfig();
        next.by_sun = 1;
        NoshiNightSetConfig(next);
        [me applySetup];
    });
}

- (void)updateLocation {
    NoshiWeakReference *weak = _weak;
    NoshiNightRequestLocation(^(BOOL known) {
        NoshiNightModeController *me = weak.target;
        if (!me) return;
        if (!known) NoshiGiftAlert(nil, NSLocalizedString(@"night.sun.denied", nil));
        else [me applySetup];
    });
}

- (void)chooseMode:(int32_t)mode {
    noshi_night_config config = NoshiNightConfig();
    if (config.mode == mode) return;
    config.mode = mode;
    NoshiNightSetConfig(config);
    [self applySetup];
}

- (void)chooseTimeForStart:(BOOL)start {
    NSMutableArray *options = [NSMutableArray array];
    for (int i = 0; i < TIMES_PER_DAY; ++i) [options addObject:NoshiClockText(i * TIME_STEP)];
    NoshiWeakReference *weak = _weak;
    NoshiSettingsChoose(self, NSLocalizedString(start ? @"night.from" : @"night.to", nil), options, ^(NSUInteger index) {
        NoshiNightModeController *me = weak.target;
        if (!me) return;
        noshi_night_config next = NoshiNightConfig();
        if (start) next.from_minute = (int32_t)(index * TIME_STEP);
        else next.to_minute = (int32_t)(index * TIME_STEP);
        NoshiNightSetConfig(next);
        [me applySetup];
    });
}

/* the slider moves in many steps; each is stored, and the theme follows at the next look, so the page does not leave from under the finger */
- (void)thresholdMoved:(float)value {
    noshi_night_config config = NoshiNightConfig();
    int32_t percent = (int32_t)(value + 0.5f);
    if (percent == config.threshold_percent) return;
    config.threshold_percent = percent;
    NoshiNightSetConfig(config);
    NSString *info = [NSString stringWithFormat:NSLocalizedString(@"night.brightness.info", nil), (int)percent];
    [self setFooter:info forSectionAtIndex:1];
}

@end

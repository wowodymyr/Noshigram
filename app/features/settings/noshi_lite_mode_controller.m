#import "noshi_lite_mode_controller.h"

#import "noshi_alert.h"
#import "noshi_lite_mode.h"
#import "noshi_weak_reference.h"

/* the sections, in the order of the screen */
enum { SectionLevel, SectionOptions, SectionTransitions, SectionClass };

@interface NoshiLiteModeSettingsController () {
    NoshiWeakReference *_weak;
    BOOL _builtUnderSaver;
}
@end

@implementation NoshiLiteModeSettingsController

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"lite.title", nil);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_weak clear];
    [_weak release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(liteModeChanged) name:NoshiLiteModeDidChangeNotification object:nil];
    [self rebuild];
}

#pragma mark texts

static NSString *NoshiPercentText(int percent) {
    return [NSString stringWithFormat:@"%d%%", percent];
}

/* what the footer under the slider says of a level */
static NSString *NoshiLevelInfo(int percent) {
    if (percent <= 0) return NSLocalizedString(@"lite.battery.info.off", nil);
    if (percent >= 100) return NSLocalizedString(@"lite.battery.info.on", nil);
    return [NSString stringWithFormat:NSLocalizedString(@"lite.battery.info.below", nil), NoshiPercentText(percent)];
}

static NSDictionary *NoshiLevelDescription(int percent) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (percent <= 0) {
        [info setObject:NSLocalizedString(@"lite.battery.always.off", nil) forKey:@"line"];
        [info setObject:NSLocalizedString(@"lite.battery.off", nil) forKey:@"short"];
        [info setObject:[NSNumber numberWithBool:YES] forKey:@"left"];
    } else if (percent >= 100) {
        [info setObject:NSLocalizedString(@"lite.battery.always.on", nil) forKey:@"line"];
        [info setObject:NSLocalizedString(@"lite.battery.on", nil) forKey:@"short"];
        [info setObject:[NSNumber numberWithBool:YES] forKey:@"right"];
    } else {
        [info setObject:[NSString stringWithFormat:NSLocalizedString(@"lite.battery.below", nil), NoshiPercentText(percent)] forKey:@"line"];
        [info setObject:NoshiPercentText(percent) forKey:@"short"];
        [info setObject:[NSNumber numberWithFloat:(float)percent / 100.0f] forKey:@"fill"];
        /* the badge says whether the saver is working at this moment, which the battery decides */
        BOOL applied = noshi_lite_power_saver_applied(percent, NoshiLiteBatteryPercent()) != 0;
        [info setObject:NSLocalizedString(applied ? @"lite.battery.on" : @"lite.battery.off", nil) forKey:@"badge"];
    }
    return info;
}

- (NSArray *)classNames {
    return [NSArray arrayWithObjects:[NSString stringWithFormat:@"%@ [%@]", NSLocalizedString(@"lite.class.auto", nil), NoshiLiteClassName(NoshiLiteMeasuredClass())],
            NSLocalizedString(@"lite.class.high", nil), NSLocalizedString(@"lite.class.average", nil), NSLocalizedString(@"lite.class.low", nil), nil];
}

#pragma mark sections

- (NoshiSettingsSection *)levelSection {
    NoshiWeakReference *weak = _weak;
    NoshiSettingsRow *level = [NoshiSettingsRow levelRowWithTitle:NSLocalizedString(@"lite.battery.title", nil) leftCaption:NSLocalizedString(@"lite.battery.off", nil)
                                                        rightCaption:NSLocalizedString(@"lite.battery.on", nil) percent:NoshiLitePowerSaverLevel()
                                                            describe:^NSDictionary *(int percent) { return NoshiLevelDescription(percent); }
                                                              change:^(int percent) {
        NoshiLiteSetPowerSaverLevel(percent);
        [(NoshiLiteModeSettingsController *)weak.target setFooter:NoshiLevelInfo(percent) forSectionAtIndex:SectionLevel];
    }];
    return [NoshiSettingsSection sectionWithHeader:nil footer:NoshiLevelInfo(NoshiLitePowerSaverLevel()) rows:[NSArray arrayWithObject:level]];
}

/* a switch of one animation; the power saver holds them all off, and a touch on a row says so */
- (NoshiSettingsRow *)switchForFlag:(uint32_t)flag symbol:(NoshiSymbol)symbol tone:(NoshiSettingsTone)tone key:(NSString *)key {
    BOOL saver = NoshiLitePowerSaverApplied();
    NoshiSettingsRow *row = [NoshiSettingsRow switchRowWithSymbol:symbol tone:tone title:NSLocalizedString(key, nil) subtitle:nil on:NoshiLiteEnabled(flag)
                                                              toggle:^(BOOL on) { NoshiLiteSetFlag(flag, on); }];
    if (saver) {
        row.disabled = YES;
        row.tap = ^{ NoshiShowNotice(nil, NSLocalizedString(@"lite.restricted", nil)); };
    }
    return row;
}

- (NoshiSettingsSection *)optionsSection {
    _builtUnderSaver = NoshiLitePowerSaverApplied();
    NSArray *rows = [NSArray arrayWithObjects:
        [self switchForFlag:NOSHI_LITE_STICKERS_CHAT symbol:NoshiSymbolSticker tone:NoshiSettingsToneOrangeDeep key:@"lite.stickers"],
        [self switchForFlag:NOSHI_LITE_EMOJI_CHAT symbol:NoshiSymbolSmiley tone:NoshiSettingsToneOrangeBright key:@"lite.emoji"],
        [self switchForFlag:NOSHI_LITE_CHAT_BACKGROUND symbol:NoshiSymbolChats tone:NoshiSettingsTonePurple key:@"lite.background"],
        [self switchForFlag:NOSHI_LITE_CHAT_SCALE symbol:NoshiSymbolMagnifier tone:NoshiSettingsToneBlue key:@"lite.zoom"],
        [self switchForFlag:NOSHI_LITE_CHAT_THANOS symbol:NoshiSymbolTrashCan tone:NoshiSettingsToneRed key:@"lite.dust"],
        [self switchForFlag:NOSHI_LITE_CALLS symbol:NoshiSymbolPhone tone:NoshiSettingsToneGreen key:@"lite.calls"], nil];
    return [NoshiSettingsSection sectionWithHeader:NSLocalizedString(@"lite.options", nil) footer:nil rows:rows];
}

- (NoshiSettingsSection *)transitionsSection {
    NoshiSettingsRow *smooth = [NoshiSettingsRow switchRowWithTitle:NSLocalizedString(@"lite.smooth", nil) subtitle:nil on:NoshiLiteSmoothTransitions()
                                                                toggle:^(BOOL on) { NoshiLiteSetSmoothTransitions(on); }];
    return [NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"lite.smooth.info", nil) rows:[NSArray arrayWithObject:smooth]];
}

- (NoshiSettingsSection *)classSection {
    NoshiWeakReference *weak = _weak;
    NSArray *names = [self classNames];
    NoshiSettingsRow *row = [NoshiSettingsRow rowWithTitle:NSLocalizedString(@"lite.class", nil) value:[names objectAtIndex:(NSUInteger)NoshiLiteClassChoice()] tap:^{
        NoshiLiteModeSettingsController *screen = weak.target;
        NoshiSettingsChoose(screen, NSLocalizedString(@"lite.class", nil), names, ^(NSUInteger index) {
            if ((int)index == NoshiLiteClassChoice()) return;
            NoshiLiteSetClassChoice((int)index);
            NoshiLiteModeSettingsController *again = weak.target;
            [again replaceSectionAtIndex:SectionClass withSection:[again classSection]];
            /* the class picks the switches of a person who never moved one */
            [again replaceSectionAtIndex:SectionOptions withSection:[again optionsSection]];
        });
    }];
    return [NoshiSettingsSection sectionWithHeader:nil footer:nil rows:[NSArray arrayWithObject:row]];
}

- (void)rebuild {
    self.sections = [NSArray arrayWithObjects:[self levelSection], [self optionsSection], [self transitionsSection], [self classSection], nil];
}

/* the saver came or went: the switches are made again, and the slider under the finger is left alone */
- (void)liteModeChanged {
    if (!self.sections.count || NoshiLitePowerSaverApplied() == _builtUnderSaver) return;
    [self replaceSectionAtIndex:SectionOptions withSection:[self optionsSection]];
}

@end

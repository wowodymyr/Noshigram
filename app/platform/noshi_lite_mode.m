#import "noshi_lite_mode.h"

#import <UIKit/UIKit.h>

NSString *const NoshiLiteModeDidChangeNotification = @"NoshiLiteModeDidChange";

static NSString *const NoshiLiteFlagsKey = @"noshigram.lite";
static NSString *const NoshiLiteLevelKey = @"noshigram.lite.level";
static NSString *const NoshiLiteSmoothKey = @"noshigram.lite.smooth";
static NSString *const NoshiLiteClassKey = @"noshigram.lite.class";
static NSString *const NoshiLitePremiumKey = @"noshigram.lite.premium";

/* the level the power saver starts at for a person who never set one; takes 10 percent for every class */
#define DEFAULT_LEVEL 10

static BOOL sApplied;
static BOOL sStarted;

static NSUserDefaults *Defaults(void) {
    return [NSUserDefaults standardUserDefaults];
}

static void Announce(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiLiteModeDidChangeNotification object:nil];
}

noshi_lite_class NoshiLiteMeasuredClass(void) {
    NSProcessInfo *info = [NSProcessInfo processInfo];
    return noshi_lite_measure_class((uint64_t)[info physicalMemory], (unsigned)[info processorCount]);
}

int NoshiLiteClassChoice(void) {
    NSInteger choice = [Defaults() integerForKey:NoshiLiteClassKey];
    return choice >= 0 && choice <= 3 ? (int)choice : 0;
}

noshi_lite_class NoshiLiteClass(void) {
    switch (NoshiLiteClassChoice()) {
    case 1: return NOSHI_LITE_CLASS_HIGH;
    case 2: return NOSHI_LITE_CLASS_AVERAGE;
    case 3: return NOSHI_LITE_CLASS_LOW;
    default: return NoshiLiteMeasuredClass();
    }
}

void NoshiLiteSetClassChoice(int choice) {
    [Defaults() setInteger:choice forKey:NoshiLiteClassKey];
    Announce();
}

NSString *NoshiLiteClassName(noshi_lite_class device_class) {
    switch (device_class) {
    case NOSHI_LITE_CLASS_LOW: return NSLocalizedString(@"lite.class.low", nil);
    case NOSHI_LITE_CLASS_AVERAGE: return NSLocalizedString(@"lite.class.average", nil);
    default: return NSLocalizedString(@"lite.class.high", nil);
    }
}

/* the stored flags, or what the class gives to a person who never changed one */
static uint32_t StoredValue(void) {
    id stored = [Defaults() objectForKey:NoshiLiteFlagsKey];
    return [stored isKindOfClass:[NSNumber class]] ? (uint32_t)[stored unsignedIntValue] : noshi_lite_default_value(NoshiLiteClass());
}

int NoshiLitePowerSaverLevel(void) {
    id stored = [Defaults() objectForKey:NoshiLiteLevelKey];
    return [stored isKindOfClass:[NSNumber class]] ? noshi_lite_clamp_level([stored intValue]) : DEFAULT_LEVEL;
}

int NoshiLiteBatteryPercent(void) {
    UIDevice *device = [UIDevice currentDevice];
    if (!device.batteryMonitoringEnabled) return -1;
    float level = device.batteryLevel;
    return level < 0 ? -1 : (int)(level * 100.0f + 0.5f);
}

/* the answer for now, which also tells the screens when it changed */
static BOOL AppliedNow(void) {
    return noshi_lite_power_saver_applied(NoshiLitePowerSaverLevel(), NoshiLiteBatteryPercent()) != 0;
}

static void Recheck(void) {
    BOOL applied = AppliedNow();
    if (applied == sApplied) return;
    sApplied = applied;
    Announce();
}

BOOL NoshiLitePowerSaverApplied(void) {
    return sStarted ? sApplied : AppliedNow();
}

static BOOL Premium(void) {
    return [Defaults() boolForKey:NoshiLitePremiumKey];
}

BOOL NoshiLiteEnabled(uint32_t flag) {
    return noshi_lite_enabled(StoredValue(), NoshiLitePowerSaverApplied(), flag, Premium()) != 0;
}

void NoshiLiteSetFlag(uint32_t flag, BOOL on) {
    /* the whole mask is set or cleared, so a Premium account and a plain one see the same switch */
    uint32_t value = noshi_lite_with(StoredValue(), flag, on);
    [Defaults() setObject:[NSNumber numberWithUnsignedInt:value] forKey:NoshiLiteFlagsKey];
    Announce();
}

void NoshiLiteSetPowerSaverLevel(int level) {
    [Defaults() setInteger:noshi_lite_clamp_level(level) forKey:NoshiLiteLevelKey];
    Recheck();
}

void NoshiLiteSetPremium(BOOL premium) {
    if (premium == Premium()) return;
    [Defaults() setBool:premium forKey:NoshiLitePremiumKey];
    Announce();
}

BOOL NoshiLiteSmoothTransitions(void) {
    id stored = [Defaults() objectForKey:NoshiLiteSmoothKey];
    return [stored isKindOfClass:[NSNumber class]] ? [stored boolValue] : YES;
}

/* UIKit animates its own transitions and sheets through UIView, and this switch stops all of them at once */
static void ApplySmooth(void) {
    [UIView setAnimationsEnabled:NoshiLiteSmoothTransitions()];
}

void NoshiLiteSetSmoothTransitions(BOOL on) {
    [Defaults() setBool:on forKey:NoshiLiteSmoothKey];
    ApplySmooth();
    Announce();
}

@interface NoshiLiteObserver : NSObject
@end

@implementation NoshiLiteObserver

- (void)batteryChanged {
    Recheck();
}

/* UIKit turns the animations back on after some system transitions, so the choice is made again when the app comes forward */
- (void)becameActive {
    ApplySmooth();
    Recheck();
}

@end

void NoshiLiteModeStart(void) {
    if (sStarted) return;
    sStarted = YES;
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;
    static NoshiLiteObserver *observer;
    observer = [[NoshiLiteObserver alloc] init];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:observer selector:@selector(batteryChanged) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [center addObserver:observer selector:@selector(batteryChanged) name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [center addObserver:observer selector:@selector(becameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    sApplied = AppliedNow();
    ApplySmooth();
}

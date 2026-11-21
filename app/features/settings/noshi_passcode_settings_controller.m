#import "noshi_passcode_settings_controller.h"

#import "noshi_biometric.h"
#import "noshi_passcode_flow_controller.h"
#import "noshi_passcode_store.h"
#import "noshi_theme.h"
#import "noshi_weak_reference.h"

/* the choices: never, at every return, and after a minute, five minutes, an hour or five hours away */
static const uint32_t NoshiAutoLockSeconds[] = {0, NOSHI_PASSCODE_AT_ONCE, 60, 5 * 60, 60 * 60, 5 * 60 * 60};
static NSString *const NoshiAutoLockKeys[] = {@"passcode.auto.never", @"passcode.auto.now", @"passcode.auto.1m", @"passcode.auto.5m", @"passcode.auto.1h", @"passcode.auto.5h"};
#define AUTO_LOCK_CHOICES (sizeof(NoshiAutoLockSeconds) / sizeof(NoshiAutoLockSeconds[0]))

static NSString *NoshiAutoLockTitle(uint32_t seconds) {
    for (NSUInteger i = 0; i < AUTO_LOCK_CHOICES; ++i) {
        if (NoshiAutoLockSeconds[i] == seconds) return NSLocalizedString(NoshiAutoLockKeys[i], nil);
    }
    return [NSString stringWithFormat:NSLocalizedString(@"passcode.auto.seconds", nil), (unsigned long)seconds];
}

@interface NoshiPasscodeSettingsController () {
    NoshiWeakReference *_weak;
}
@end

@implementation NoshiPasscodeSettingsController

+ (void)openFrom:(UIViewController *)host push:(void (^)(UIViewController *))push {
    void (^open)(void) = ^{ push([[[NoshiPasscodeSettingsController alloc] init] autorelease]); };
    if (!NoshiPasscodeEnabled()) {
        open();
        return;
    }
    NoshiPasscodeFlowController *flow = [[[NoshiPasscodeFlowController alloc] initWithMode:NoshiPasscodeFlowVerify completion:^(BOOL done) {
        if (done) open();
    }] autorelease];
    [host presentViewController:flow animated:YES completion:nil];
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _weak = [[NoshiWeakReference referenceTo:self] retain];
    self.pageTitle = NSLocalizedString(@"passcode.title", nil);
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
    return [[[NoshiPasscodeSettingsController alloc] init] autorelease];
}

- (void)setUpCode {
    NoshiWeakReference *weak = _weak;
    NoshiPasscodeFlowController *flow = [[[NoshiPasscodeFlowController alloc] initWithMode:NoshiPasscodeFlowSetup completion:^(BOOL done) {
        (void)done;
        [(NoshiPasscodeSettingsController *)weak.target rebuild];
    }] autorelease];
    [self presentViewController:flow animated:YES completion:nil];
}

/* the sensor is asked once before the switch stays on, so a face or finger that cannot be read never leaves a lock that only looks safe */
- (void)setBiometric:(BOOL)on {
    if (!on) {
        NoshiPasscodeSetBiometric(NO);
        [self rebuild];
        return;
    }
    NoshiWeakReference *weak = _weak;
    NoshiBiometricEvaluate(NSLocalizedString(@"passcode.biometric.reason", nil), ^(BOOL matched) {
        if (matched) NoshiPasscodeSetBiometric(YES);
        [(NoshiPasscodeSettingsController *)weak.target rebuild];
    });
}

- (void)chooseAutoLock {
    NoshiWeakReference *weak = _weak;
    NSMutableArray *options = [NSMutableArray array];
    for (NSUInteger i = 0; i < AUTO_LOCK_CHOICES; ++i) [options addObject:NSLocalizedString(NoshiAutoLockKeys[i], nil)];
    NoshiSettingsChoose(self, NSLocalizedString(@"passcode.auto", nil), options, ^(NSUInteger index) {
        if (index >= AUTO_LOCK_CHOICES) return;
        NoshiPasscodeSetAutoLock(NoshiAutoLockSeconds[index]);
        [(NoshiPasscodeSettingsController *)weak.target rebuild];
    });
}

- (void)rebuild {
    NoshiWeakReference *weak = _weak;
    BOOL enabled = NoshiPasscodeEnabled();
    NSMutableArray *sections = [NSMutableArray array];
    NoshiSettingsRow *toggle = [NoshiSettingsRow switchRowWithSymbol:NoshiSymbolLock tone:NoshiSettingsToneGreen title:NSLocalizedString(@"passcode.title", nil)
                                                                subtitle:nil on:enabled toggle:^(BOOL on) {
        NoshiPasscodeSettingsController *me = weak.target;
        if (!me) return;
        if (on) {
            [me setUpCode];
            return;
        }
        NoshiPasscodeClear();
        [me rebuild];
    }];
    [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"passcode.info", nil) rows:[NSArray arrayWithObject:toggle]]];
    if (enabled) {
        NoshiSettingsRow *change = [NoshiSettingsRow rowWithSymbol:NoshiSymbolLock tone:NoshiSettingsToneBlue title:NSLocalizedString(@"passcode.change", nil)
                                                              subtitle:nil value:nil tap:^{ [(NoshiPasscodeSettingsController *)weak.target setUpCode]; }];
        NoshiSettingsRow *auto_ = [NoshiSettingsRow rowWithSymbol:NoshiSymbolClock tone:NoshiSettingsToneOrange title:NSLocalizedString(@"passcode.auto", nil)
                                                             subtitle:nil value:NoshiAutoLockTitle(NoshiPasscodeAutoLock())
                                                                  tap:^{ [(NoshiPasscodeSettingsController *)weak.target chooseAutoLock]; }];
        [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:NSLocalizedString(@"passcode.auto.info", nil)
                                                                 rows:[NSArray arrayWithObjects:change, auto_, nil]]];
        NoshiBiometricKind kind = NoshiBiometricAvailable();
        if (kind != NoshiBiometricNone) {
            NoshiSettingsRow *sensor = [NoshiSettingsRow switchRowWithSymbol:NoshiSymbolLock tone:NoshiSettingsTonePurple title:NoshiBiometricName(kind)
                                                                        subtitle:nil on:NoshiPasscodeBiometricEnabled() toggle:^(BOOL on) {
                [(NoshiPasscodeSettingsController *)weak.target setBiometric:on];
            }];
            [sections addObject:[NoshiSettingsSection sectionWithHeader:nil footer:[NSString stringWithFormat:NSLocalizedString(@"passcode.biometric.info", nil), NoshiBiometricName(kind)]
                                                                     rows:[NSArray arrayWithObject:sensor]]];
        }
    }
    self.sections = sections;
    [self reloadSettings];
}

@end

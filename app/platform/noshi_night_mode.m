#import "noshi_night_mode.h"

#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

#import <objc/message.h>

#import "noshi_theme.h"

NSString *const NoshiNightModeDidChangeNotification = @"NoshiNightModeDidChange";

static NSString *const NoshiNightModeKey = @"noshigram.night.mode";
static NSString *const NoshiNightFromKey = @"noshigram.night.from";
static NSString *const NoshiNightToKey = @"noshigram.night.to";
static NSString *const NoshiNightThresholdKey = @"noshigram.night.threshold";
static NSString *const NoshiNightBySunKey = @"noshigram.night.bysun";
static NSString *const NoshiNightSunsetKey = @"noshigram.night.sunset";
static NSString *const NoshiNightSunriseKey = @"noshigram.night.sunrise";
static NSString *const NoshiNightSunStateKey = @"noshigram.night.sunstate";
/* the place the phone was last found at, and the day (year * 10000 + month * 100 + day) the sun times were worked out for */
static NSString *const NoshiNightLatitudeKey = @"noshigram.night.latitude";
static NSString *const NoshiNightLongitudeKey = @"noshigram.night.longitude";
static NSString *const NoshiNightSunDayKey = @"noshigram.night.sunday";
#define NIGHT_LOOK_SECONDS 30.0
/* the brightness slider of the system moves in many small steps, and one look after the last of them is enough */
#define NIGHT_BRIGHTNESS_DELAY 2.0

/* the decision of the last look that had one; -1 before it */
static int NoshiNightLast = -1;
static NSTimer *NoshiNightTimer;
static BOOL (^NoshiNightGate)(void);

@interface NoshiNightObserver : NSObject
+ (NoshiNightObserver *)shared;
- (void)look;
- (void)brightnessChanged;
@end

noshi_night_config NoshiNightConfig(void) {
    noshi_night_config config;
    noshi_night_config_default(&config);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    noshi_night_config stored = config;
    if ([defaults objectForKey:NoshiNightModeKey]) stored.mode = (int32_t)[defaults integerForKey:NoshiNightModeKey];
    if ([defaults objectForKey:NoshiNightFromKey]) stored.from_minute = (int32_t)[defaults integerForKey:NoshiNightFromKey];
    if ([defaults objectForKey:NoshiNightToKey]) stored.to_minute = (int32_t)[defaults integerForKey:NoshiNightToKey];
    if ([defaults objectForKey:NoshiNightThresholdKey]) stored.threshold_percent = (int32_t)[defaults integerForKey:NoshiNightThresholdKey];
    if ([defaults objectForKey:NoshiNightBySunKey]) stored.by_sun = (int32_t)[defaults integerForKey:NoshiNightBySunKey];
    if ([defaults objectForKey:NoshiNightSunsetKey]) stored.sunset_minute = (int32_t)[defaults integerForKey:NoshiNightSunsetKey];
    if ([defaults objectForKey:NoshiNightSunriseKey]) stored.sunrise_minute = (int32_t)[defaults integerForKey:NoshiNightSunriseKey];
    if ([defaults objectForKey:NoshiNightSunStateKey]) stored.sun_state = (int32_t)[defaults integerForKey:NoshiNightSunStateKey];
    /* a stored value that is out of range (a file edited by hand) falls back to the default as a whole */
    return noshi_night_config_valid(&stored) ? stored : config;
}

void NoshiNightSetConfig(noshi_night_config config) {
    if (!noshi_night_config_valid(&config)) {
        NSLog(@"noshigram: the night mode setup is out of range and was not stored");
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:config.mode forKey:NoshiNightModeKey];
    [defaults setInteger:config.from_minute forKey:NoshiNightFromKey];
    [defaults setInteger:config.to_minute forKey:NoshiNightToKey];
    [defaults setInteger:config.threshold_percent forKey:NoshiNightThresholdKey];
    [defaults setInteger:config.by_sun forKey:NoshiNightBySunKey];
    [defaults setInteger:config.sunset_minute forKey:NoshiNightSunsetKey];
    [defaults setInteger:config.sunrise_minute forKey:NoshiNightSunriseKey];
    [defaults setInteger:config.sun_state forKey:NoshiNightSunStateKey];
    if (![defaults synchronize]) NSLog(@"noshigram: the night mode setup was not saved");
    /* a new setup is looked at fresh: what the last setup decided says nothing about this one */
    NoshiNightLast = -1;
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiNightModeDidChangeNotification object:nil];
}

BOOL NoshiNightSystemAvailable(void) {
    return [UIView instancesRespondToSelector:NSSelectorFromString(@"overrideUserInterfaceStyle")];
}

/* the appearance the system is in: 1 dark, 0 light, -1 where it has none or has not decided (UIUserInterfaceStyle is 1 for light and 2 for dark) */
static int NoshiSystemDark(void) {
    if (!NoshiNightSystemAvailable()) return -1;
    id traits = [[UIScreen mainScreen] valueForKey:@"traitCollection"];
    NSInteger style = [[traits valueForKey:@"userInterfaceStyle"] integerValue];
    return style == 2 ? 1 : (style == 1 ? 0 : -1);
}

static int32_t NoshiDayNumber(NSDate *date) {
    NSDateComponents *day = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:date];
    return (int32_t)(day.year * 10000 + day.month * 100 + day.day);
}

/* the sun times of a schedule by the sun are worked out for today from the stored place; they are only worked out
   again when the day has turned */
static void NoshiNightRefreshSun(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    noshi_night_config config = NoshiNightConfig();
    if (config.mode != NOSHI_NIGHT_SCHEDULED || !config.by_sun || ![defaults objectForKey:NoshiNightLatitudeKey]) return;
    NSDate *now = [NSDate date];
    int32_t today = NoshiDayNumber(now);
    if ([defaults integerForKey:NoshiNightSunDayKey] == today) return;
    NSDateComponents *day = [[NSCalendar currentCalendar] components:NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit fromDate:now];
    int offset = (int)([[NSTimeZone localTimeZone] secondsFromGMTForDate:now] / 60);
    int32_t rise = 0, set = 0, state = 0;
    if (noshi_sun_times([defaults doubleForKey:NoshiNightLatitudeKey], [defaults doubleForKey:NoshiNightLongitudeKey], (int)day.year, (int)day.month, (int)day.day, offset,
                          &rise, &set, &state) != 0) {
        NSLog(@"noshigram: the sun times could not be worked out for the stored place");
        return;
    }
    config.sunrise_minute = rise;
    config.sunset_minute = set;
    config.sun_state = state;
    /* stored without the notification of a change of setup: nothing the person did changed, and the check that asked is the one that goes on */
    [defaults setInteger:config.sunset_minute forKey:NoshiNightSunsetKey];
    [defaults setInteger:config.sunrise_minute forKey:NoshiNightSunriseKey];
    [defaults setInteger:config.sun_state forKey:NoshiNightSunStateKey];
    [defaults setInteger:today forKey:NoshiNightSunDayKey];
}

int NoshiNightDecision(void) {
    NoshiNightRefreshSun();
    noshi_night_config config = NoshiNightConfig();
    NSDateComponents *now = [[NSCalendar currentCalendar] components:NSHourCalendarUnit | NSMinuteCalendarUnit fromDate:[NSDate date]];
    int32_t minute = (int32_t)(now.hour * 60 + now.minute);
    int32_t brightness = (int32_t)([UIScreen mainScreen].brightness * 100.0f + 0.5f);
    return noshi_night_decide(&config, minute, brightness, NoshiSystemDark());
}

#pragma mark location

@interface NoshiNightLocator : NSObject <CLLocationManagerDelegate> {
    CLLocationManager *_manager;
    /* everyone who asked while a request was out, answered together */
    NSMutableArray *_waiters;
}
- (void)requestWithCompletion:(void (^)(BOOL known))completion;
@end

@implementation NoshiNightLocator

- (void)dealloc {
    _manager.delegate = nil;
    [_manager release];
    [_waiters release];
    [super dealloc];
}

- (void)finish:(BOOL)known {
    [_manager stopUpdatingLocation];
    _manager.delegate = nil;
    [_manager release];
    _manager = nil;
    NSArray *waiters = [_waiters autorelease];
    _waiters = nil;
    for (void (^done)(BOOL) in waiters) done(known);
}

- (void)requestWithCompletion:(void (^)(BOOL known))completion {
    if (_manager) {
        [_waiters addObject:[[completion copy] autorelease]];
        return;
    }
    if (![CLLocationManager locationServicesEnabled]) {
        completion(NO);
        return;
    }
    _waiters = [[NSMutableArray alloc] initWithObjects:[[completion copy] autorelease], nil];
    _manager = [[CLLocationManager alloc] init];
    _manager.delegate = self;
    _manager.desiredAccuracy = kCLLocationAccuracyKilometer;
    SEL ask = NSSelectorFromString(@"requestWhenInUseAuthorization");
    if ([_manager respondsToSelector:ask]) ((void (*)(id, SEL))objc_msgSend)(_manager, ask);
    [_manager startUpdatingLocation];
}

/* a place was found: kept, and the sun times are worked out again from it at the next look */
- (void)useLocation:(CLLocation *)place {
    if (!place || place.horizontalAccuracy < 0) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:place.coordinate.latitude forKey:NoshiNightLatitudeKey];
    [defaults setDouble:place.coordinate.longitude forKey:NoshiNightLongitudeKey];
    [defaults removeObjectForKey:NoshiNightSunDayKey];
    if (![defaults synchronize]) NSLog(@"noshigram: the place of the night schedule was not saved");
    [self finish:YES];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    (void)manager;
    [self useLocation:[locations lastObject]];
}

/* ios 5 calls this older method instead of the one above, which came with ios 6 */
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)place fromLocation:(CLLocation *)old {
    (void)manager;
    (void)old;
    [self useLocation:place];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager;
    /* the first answer can be "not yet", and the manager goes on looking; only a refusal ends the request */
    if (error.code == kCLErrorDenied) [self finish:NO];
}

@end

static NoshiNightLocator *NoshiNightLocatorShared;

void NoshiNightRequestLocation(void (^completion)(BOOL known)) {
    if (!NoshiNightLocatorShared) NoshiNightLocatorShared = [[NoshiNightLocator alloc] init];
    [NoshiNightLocatorShared requestWithCompletion:completion];
}

BOOL NoshiNightHasLocation(void) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:NoshiNightLatitudeKey] != nil;
}

BOOL NoshiNightCheck(BOOL announce) {
    int decision = NoshiNightDecision();
    if (decision == -1) {
        NoshiNightLast = -1;
        return NO;
    }
    BOOL change = noshi_night_should_switch(decision, NoshiNightLast, NoshiThemeStoredDark()) != 0;
    NoshiNightLast = decision;
    if (!change) return NO;
    NoshiThemeStoreDark(decision == 1);
    if (announce) [[NSNotificationCenter defaultCenter] postNotificationName:NoshiThemeDidChangeNotification object:nil];
    return YES;
}

@implementation NoshiNightObserver

+ (NoshiNightObserver *)shared {
    static NoshiNightObserver *observer;
    if (!observer) observer = [[NoshiNightObserver alloc] init];
    return observer;
}

/* a look that cannot be shown is not counted: the decision stays unseen, and the next look finds the change again */
- (void)look {
    if (NoshiNightGate && !NoshiNightGate()) return;
    NoshiNightCheck(YES);
}

/* the timer fires in the background too while the app is kept awake for its link, and a theme nobody sees is not worth the wake */
- (void)enteredBackground {
    [NoshiNightTimer invalidate];
    [NoshiNightTimer release];
    NoshiNightTimer = nil;
}

- (void)becameActive {
    if (!NoshiNightTimer) NoshiNightTimer = [[NSTimer scheduledTimerWithTimeInterval:NIGHT_LOOK_SECONDS target:self selector:@selector(look) userInfo:nil repeats:YES] retain];
    [self look];
}

- (void)brightnessChanged {
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(look) object:nil];
    [self performSelector:@selector(look) withObject:nil afterDelay:NIGHT_BRIGHTNESS_DELAY];
}

@end

void NoshiNightStart(BOOL (^gate)(void)) {
    NoshiNightStop();
    NoshiNightGate = [gate copy];
    NoshiNightObserver *observer = [NoshiNightObserver shared];
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground)
        NoshiNightTimer = [[NSTimer scheduledTimerWithTimeInterval:NIGHT_LOOK_SECONDS target:observer selector:@selector(look) userInfo:nil repeats:YES] retain];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:observer selector:@selector(becameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:observer selector:@selector(enteredBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:observer selector:@selector(brightnessChanged) name:UIScreenBrightnessDidChangeNotification object:nil];
    /* a change of the setup is looked at at once */
    [center addObserver:observer selector:@selector(look) name:NoshiNightModeDidChangeNotification object:nil];
}

void NoshiNightStop(void) {
    NoshiNightObserver *observer = [NoshiNightObserver shared];
    [NSObject cancelPreviousPerformRequestsWithTarget:observer];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    [NoshiNightTimer invalidate];
    [NoshiNightTimer release];
    NoshiNightTimer = nil;
    [NoshiNightGate release];
    NoshiNightGate = nil;
}

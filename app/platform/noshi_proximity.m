#import "noshi_proximity.h"

#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

NSString *const NoshiProximityDidChangeNotification = @"NoshiProximityDidChange";

/* gravity along the screen's axis of view at which the phone counts as lying flat, in g: held to the ear it is tilted well past this */
#define FLAT_LIMIT 0.7
#define MOTION_INTERVAL 0.2

static NSInteger NoshiProximityUsers;
static CMMotionManager *NoshiMotion;

@interface NoshiProximityRelay : NSObject
+ (NoshiProximityRelay *)shared;
- (void)changed;
@end

@implementation NoshiProximityRelay

+ (NoshiProximityRelay *)shared {
    static NoshiProximityRelay *relay;
    if (!relay) relay = [[NoshiProximityRelay alloc] init];
    return relay;
}

- (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:NoshiProximityDidChangeNotification object:nil];
}

@end

BOOL NoshiProximityAvailable(void) {
    static BOOL known, available;
    if (known) return available;
    known = YES;
    UIDevice *device = [UIDevice currentDevice];
    BOOL wasOn = device.proximityMonitoringEnabled;
    device.proximityMonitoringEnabled = YES;
    available = device.proximityMonitoringEnabled;
    device.proximityMonitoringEnabled = wasOn;
    return available;
}

BOOL NoshiProximityStart(void) {
    UIDevice *device = [UIDevice currentDevice];
    if (NoshiProximityUsers == 0) {
        device.proximityMonitoringEnabled = YES;
        /* a device with no sensor leaves the property off */
        if (!device.proximityMonitoringEnabled) return NO;
        [[NSNotificationCenter defaultCenter] addObserver:[NoshiProximityRelay shared] selector:@selector(changed)
                                                     name:UIDeviceProximityStateDidChangeNotification object:nil];
        if ([CMMotionManager class]) {
            NoshiMotion = [[CMMotionManager alloc] init];
            if (NoshiMotion.accelerometerAvailable) {
                NoshiMotion.accelerometerUpdateInterval = MOTION_INTERVAL;
                [NoshiMotion startAccelerometerUpdates];
            }
        }
    }
    ++NoshiProximityUsers;
    return YES;
}

void NoshiProximityStop(void) {
    if (NoshiProximityUsers == 0) return;
    if (--NoshiProximityUsers > 0) return;
    [[NSNotificationCenter defaultCenter] removeObserver:[NoshiProximityRelay shared] name:UIDeviceProximityStateDidChangeNotification object:nil];
    [UIDevice currentDevice].proximityMonitoringEnabled = NO;
    [NoshiMotion stopAccelerometerUpdates];
    [NoshiMotion release];
    NoshiMotion = nil;
}

BOOL NoshiProximityNear(void) {
    return NoshiProximityUsers > 0 && [UIDevice currentDevice].proximityState;
}

BOOL NoshiPhoneIsUpright(void) {
    CMAccelerometerData *sample = NoshiMotion.accelerometerData;
    if (!sample) return YES;
    return fabs(sample.acceleration.z) < FLAT_LIMIT;
}

#import "noshi_power_notice.h"

#import <UIKit/UIKit.h>
#import "noshi_inapp_banner.h"
#import "noshi_lite_mode.h"

@interface NoshiPowerNotice : NSObject {
    noshi_power_notice_state _state;
}
- (void)check;
@end

@implementation NoshiPowerNotice
- (void)check {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    int battery = NoshiLiteBatteryPercent();
    int saver = noshi_lite_power_saver_applied(NoshiLitePowerSaverLevel(), battery);
    uint32_t events = noshi_power_notice_update(&_state, battery, saver);
    if (!events) return;
    NSString *title = NSLocalizedString((events & NOSHI_POWER_NOTICE_LOW) ? @"power.notice.low" : @"power.notice.saver", nil);
    NSString *body = (events & NOSHI_POWER_NOTICE_SAVER) ? NSLocalizedString(@"power.notice.active", nil) : NSLocalizedString(@"power.notice.charge", nil);
    [NoshiInAppBanner showPowerTitle:title body:body];
}
@end

void NoshiPowerNoticeStart(void) {
    static NoshiPowerNotice *notice;
    if (notice) return;
    notice = [[NoshiPowerNotice alloc] init];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:notice selector:@selector(check) name:UIDeviceBatteryLevelDidChangeNotification object:nil];
    [center addObserver:notice selector:@selector(check) name:UIDeviceBatteryStateDidChangeNotification object:nil];
    [center addObserver:notice selector:@selector(check) name:NoshiLiteModeDidChangeNotification object:nil];
    [center addObserver:notice selector:@selector(check) name:UIApplicationDidBecomeActiveNotification object:nil];
    [notice check];
}

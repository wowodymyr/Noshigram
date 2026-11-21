#import "noshi_call_route.h"

#import "noshi_audio_session.h"
#import "noshi_settings_kit.h"

/* the routes the call can take now, in the order the sheet lists them, with the names they carry */
static void NoshiCallRouteOptions(NSMutableArray *names, NSMutableArray *routes, BOOL *headset) {
    NSString *bluetoothName = nil, *wiredName = nil;
    BOOL bluetooth = NoshiAudioSessionBluetoothInputAvailable(&bluetoothName);
    BOOL wired = NoshiAudioSessionWiredAvailable(&wiredName);
    [names addObject:NSLocalizedString(@"call.route.phone", nil)];
    [routes addObject:[NSNumber numberWithInt:NoshiAudioRouteEarpiece]];
    [names addObject:NSLocalizedString(@"call.route.speaker", nil)];
    [routes addObject:[NSNumber numberWithInt:NoshiAudioRouteSpeaker]];
    if (wired) {
        [names addObject:wiredName.length ? wiredName : NSLocalizedString(@"call.route.wired", nil)];
        [routes addObject:[NSNumber numberWithInt:NoshiAudioRouteWired]];
    }
    if (bluetooth) {
        [names addObject:bluetoothName.length ? bluetoothName : NSLocalizedString(@"call.route.bluetooth", nil)];
        [routes addObject:[NSNumber numberWithInt:NoshiAudioRouteBluetooth]];
    }
    if (headset) *headset = wired || bluetooth;
}

static BOOL NoshiCallPresentRoutes(UIViewController *host, BOOL always, void (^done)(NoshiAudioRoute route)) {
    NSMutableArray *names = [NSMutableArray array], *routes = [NSMutableArray array];
    BOOL headset = NO;
    NoshiCallRouteOptions(names, routes, &headset);
    if (!host || (!headset && !always)) return NO;
    void (^finished)(NoshiAudioRoute) = [done copy];
    NoshiSettingsChoose(host, NSLocalizedString(@"call.route.title", nil), names, ^(NSUInteger index) {
        if (index >= routes.count) return;
        NoshiAudioRoute route = (NoshiAudioRoute)[[routes objectAtIndex:index] intValue];
        if (!NoshiAudioSessionSelectRoute(route)) NSLog(@"noshigram: the call route %d was not applied", (int)route);
        if (finished) finished(route);
    });
    [finished release];
    return YES;
}

BOOL NoshiCallPresentRouteSheet(UIViewController *host, void (^done)(NoshiAudioRoute route)) {
    return NoshiCallPresentRoutes(host, NO, done);
}

BOOL NoshiCallPresentRouteChoices(UIViewController *host, void (^done)(NoshiAudioRoute route)) {
    return NoshiCallPresentRoutes(host, YES, done);
}

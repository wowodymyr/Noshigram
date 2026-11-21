#import "noshi_traffic_store.h"

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>

#include "noshi_mt_traffic.h"

static NSString *const NoshiTrafficKey = @"noshigram.traffic";
static NSTimer *NoshiTrafficTimer;

BOOL NoshiNetworkOnCellular(void) {
    struct ifaddrs *list = NULL;
    BOOL wifi = NO;
    if (getifaddrs(&list) != 0) return NO;
    for (struct ifaddrs *at = list; at; at = at->ifa_next) {
        if (!at->ifa_addr || at->ifa_addr->sa_family != AF_INET || strcmp(at->ifa_name, "en0") != 0) continue;
        if ((at->ifa_flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING)) continue;
        struct in_addr address = ((struct sockaddr_in *)at->ifa_addr)->sin_addr;
        /* a link-local address (169.254) means the Wi-Fi has no network behind it */
        if (address.s_addr != 0 && (ntohl(address.s_addr) >> 16) != 0xA9FE) wifi = YES;
    }
    freeifaddrs(list);
    return !wifi;
}

static NSDictionary *NoshiTrafficStored(void) {
    NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:NoshiTrafficKey];
    return stored ? stored : [NSDictionary dictionary];
}

static unsigned long long NoshiTrafficNumber(NSDictionary *stored, NSString *key) {
    return [[stored objectForKey:key] unsignedLongLongValue];
}

void NoshiTrafficFlush(void) {
    noshi_traffic taken;
    noshi_traffic_take(&taken);
    noshi_traffic_set_cellular(NoshiNetworkOnCellular());
    NSDictionary *stored = NoshiTrafficStored();
    NSMutableDictionary *next = [NSMutableDictionary dictionaryWithDictionary:stored];
    static NSString *const sentKeys[2] = {@"sent.wifi", @"sent.cell"};
    static NSString *const receivedKeys[2] = {@"received.wifi", @"received.cell"};
    for (int i = 0; i < 2; ++i) {
        [next setObject:[NSNumber numberWithUnsignedLongLong:NoshiTrafficNumber(stored, sentKeys[i]) + taken.sent[i]] forKey:sentKeys[i]];
        [next setObject:[NSNumber numberWithUnsignedLongLong:NoshiTrafficNumber(stored, receivedKeys[i]) + taken.received[i]] forKey:receivedKeys[i]];
    }
    if (![next objectForKey:@"since"]) [next setObject:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:@"since"];
    [[NSUserDefaults standardUserDefaults] setObject:next forKey:NoshiTrafficKey];
}

NoshiTrafficTotals NoshiTrafficRead(void) {
    NoshiTrafficFlush();
    NSDictionary *stored = NoshiTrafficStored();
    NoshiTrafficTotals totals;
    totals.sent[0] = NoshiTrafficNumber(stored, @"sent.wifi");
    totals.sent[1] = NoshiTrafficNumber(stored, @"sent.cell");
    totals.received[0] = NoshiTrafficNumber(stored, @"received.wifi");
    totals.received[1] = NoshiTrafficNumber(stored, @"received.cell");
    totals.since = [[stored objectForKey:@"since"] doubleValue];
    return totals;
}

void NoshiTrafficReset(void) {
    noshi_traffic taken;
    noshi_traffic_take(&taken);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:NoshiTrafficKey];
    NoshiTrafficFlush();
}

@interface NoshiTrafficTicker : NSObject
- (void)tick;
@end

@implementation NoshiTrafficTicker
- (void)tick {
    NoshiTrafficFlush();
}
@end

void NoshiTrafficStart(void) {
    if (NoshiTrafficTimer) return;
    noshi_traffic_set_cellular(NoshiNetworkOnCellular());
    /* the timer keeps its ticker for as long as it runs, which is the life of the app */
    NoshiTrafficTimer = [[NSTimer scheduledTimerWithTimeInterval:30 target:[[[NoshiTrafficTicker alloc] init] autorelease] selector:@selector(tick)
                                                          userInfo:nil repeats:YES] retain];
}

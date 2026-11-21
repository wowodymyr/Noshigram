#import <Foundation/Foundation.h>

#import "noshi_shiro.h"

typedef enum {
    /* a Telegram server took the connection */
    NoshiProbeReachable = 0,
    /* every server stayed silent or refused */
    NoshiProbeUnreachable,
    /* the VPN is wanted and not up, so the app does not connect at all; this says nothing about the network */
    NoshiProbeBlocked
} NoshiProbeResult;

/* asks whether Telegram can be reached from here, before there is a session to find out */
@interface NoshiNetworkProbe : NSObject

+ (void)probeWithShiro:(NoshiShiro *)shiro completion:(void (^)(NoshiProbeResult result))completion;

@end

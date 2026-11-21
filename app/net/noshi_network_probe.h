#import <Foundation/Foundation.h>

typedef enum {
    /* a Telegram server took the connection */
    NoshiProbeReachable = 0,
    /* every server stayed silent or refused */
    NoshiProbeUnreachable
} NoshiProbeResult;

/* asks whether Telegram can be reached from here, before there is a session to find out */
@interface NoshiNetworkProbe : NSObject

+ (void)probeWithCompletion:(void (^)(NoshiProbeResult result))completion;

@end

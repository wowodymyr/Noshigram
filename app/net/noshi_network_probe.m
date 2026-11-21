#import "noshi_network_probe.h"
#import "noshi_proxy_settings.h"

#include "noshi_session_file.h"

/* the first data centers of the list: two different ones, so one that is blocked alone does not look like a dead network */
static const int32_t NoshiProbeDatacenters[] = {2, 4};
#define PROBE_TIMEOUT_MS 5000

@implementation NoshiNetworkProbe

+ (void)probeWithShiro:(NoshiShiro *)shiro completion:(void (^)(NoshiProbeResult))completion {
    void (^done)(NoshiProbeResult) = [completion copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NoshiProbeResult result = NoshiProbeUnreachable;
        for (size_t i = 0; i < sizeof(NoshiProbeDatacenters) / sizeof(NoshiProbeDatacenters[0]); ++i) {
            const char *host = noshi_dc_host(NoshiProbeDatacenters[i]);
            if (!host) continue;
            noshi_mt_socket socket;
            noshi_mt_socket_init(&socket);
            BOOL tunneled = NO;
            noshi_mt_client_config config;
            memset(&config, 0, sizeof(config));
            noshi_status status = NoshiProxyConnect(shiro, &socket, host, noshi_dc_port(), PROBE_TIMEOUT_MS, &config, &tunneled);
            noshi_mt_socket_close(&socket);
            if (status == NOSHI_OK) {
                result = NoshiProbeReachable;
                break;
            }
            /* a tunnel that is wanted and not up refuses every connection in the same way, so there is no second server to try */
            if (status == NOSHI_E_STATE) {
                result = NoshiProbeBlocked;
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            done(result);
            [done release];
        });
    });
}

@end

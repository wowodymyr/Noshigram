#import <Foundation/Foundation.h>
#import "noshi_proxy.h"
#import "noshi_shiro.h"
#include "noshi_mt_client.h"

extern NSString *const NoshiProxyDidChangeNotification;

/* the selected proxy is stored in the keychain; reads are safe on the link workers */
noshi_status NoshiProxyRead(noshi_proxy *proxy, BOOL *enabled);
noshi_status NoshiProxyStoreLink(NSString *link);
/* entries expose only the address and selection, never proxy credentials */
noshi_status NoshiProxyList(NSArray **entries);
noshi_status NoshiProxySelect(NSUInteger index);
noshi_status NoshiProxyRemove(NSUInteger index);
noshi_status NoshiProxySetEnabled(BOOL enabled);
NSString *NoshiProxyDisplay(void);
noshi_status NoshiProxyConnect(NoshiShiro *shiro, noshi_mt_socket *socket, const char *host, uint16_t port,
                                   int timeout, noshi_mt_client_config *config, BOOL *tunneled);

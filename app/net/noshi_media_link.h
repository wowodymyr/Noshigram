#import <Foundation/Foundation.h>

#import "noshi_remote_file.h"
#import "noshi_shiro.h"

#include "noshi_mt_client.h"
#include "noshi_tl.h"

/* hands an exported authorization to the link: its id and bytes, or the rpc error name */
typedef void (^NoshiAuthorizationDelivery)(long long authId, NSData *bytes, NSString *errorName);
/* asked for when the link's key is not signed in yet; it must call deliver once, from any thread */
typedef void (^NoshiAuthorizer)(NoshiAuthorizationDelivery deliver);
/* runs on the main thread: the file bytes, or nil and an error name (TIMEOUT, OFFLINE, an rpc error name) */
typedef void (^NoshiDownloadCompletion)(NSData *data, NSString *errorName);

/* a second connection to a data center other than the account's home, for files that live there */
@interface NoshiMediaLink : NSObject {
    int32_t _dc;
}

@property (nonatomic, readonly) int32_t dc;
/* the VPN the connection goes through when it is wanted; set before the first download */
@property (nonatomic, assign) NoshiShiro *shiro;

- (id)initWithDc:(int32_t)dc directory:(NSString *)directory deviceModel:(NSString *)deviceModel
   systemVersion:(NSString *)systemVersion appVersion:(NSString *)appVersion langCode:(NSString *)langCode;

- (void)downloadFile:(NoshiRemoteFile *)file authorizer:(NoshiAuthorizer)authorizer completion:(NoshiDownloadCompletion)completion;
/* one part of a large file: up to limit bytes from offset, fewer on the last part, none past the end */
- (void)downloadFile:(NoshiRemoteFile *)file offset:(long long)offset limit:(int32_t)limit ranged:(BOOL)ranged
          authorizer:(NoshiAuthorizer)authorizer completion:(NoshiDownloadCompletion)completion;

/* any other request on this data center, such as the statistics of a channel that it keeps. build runs on the link's thread and handler
   gets the answer there, so it must copy what it keeps and may not touch the session; a link that cannot carry the request calls
   handler with a failed result, which NoshiDownloadErrorName names OFFLINE */
- (void)invokeBuilt:(noshi_status (^)(noshi_arena *arena, noshi_tl_value **request))build
            handler:(void (^)(const noshi_mt_rpc_result *result))handler authorizer:(NoshiAuthorizer)authorizer;

/* waits for the thread to end */
- (void)stop;

@end

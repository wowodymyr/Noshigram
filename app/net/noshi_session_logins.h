#import <Foundation/Foundation.h>

#import "noshi_session.h"

/* a login from another device that the server asks the owner to confirm */
@interface NoshiUnconfirmedLogin : NSObject {
    long long _hash;
    int32_t _date;
    NSString *_device;
    NSString *_place;
}
@property (nonatomic, readonly) long long sessionHash;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly, copy) NSString *device;
/* "frankfurt am Main, Germany", empty when the server gave no place */
@property (nonatomic, readonly, copy) NSString *place;
@end

/* the logins the owner has not answered for yet; implemented in noshi_session_logins.m */
@interface NoshiSession (Logins)

/* NoshiUnconfirmedLogin items, newest first; empty when there is nothing to ask */
- (void)loadUnconfirmedLogins:(NoshiListCompletion)completion;
/* "yes, it was me" */
- (void)confirmLogin:(NoshiUnconfirmedLogin *)login completion:(void (^)(NSString *errorName))completion;
/* "no, it was not me": the session ends */
- (void)terminateLogin:(NoshiUnconfirmedLogin *)login completion:(void (^)(NSString *errorName))completion;

@end

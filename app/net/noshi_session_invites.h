#import <Foundation/Foundation.h>

#import "noshi_dialog.h"
#import "noshi_session.h"

#include "noshi_invite.h"

/* one invite link of a chat the account made; built off the main thread */
@interface NoshiInvite : NSObject {
    NSString *_link;
    NSString *_title;
    BOOL _revoked;
    BOOL _permanent;
    BOOL _requestNeeded;
    int32_t _date;
    int32_t _startDate;
    int32_t _expireDate;
    int32_t _usageLimit;
    int32_t _usage;
    int32_t _requested;
}
@property (nonatomic, readonly, copy) NSString *link;
/* empty when the link has no name */
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) BOOL revoked;
/* the link the chat was made with; the server replaces it when it is revoked */
@property (nonatomic, readonly) BOOL permanent;
@property (nonatomic, readonly) BOOL requestNeeded;
@property (nonatomic, readonly) int32_t date;
/* unix time the link ends, zero for one that does not */
@property (nonatomic, readonly) int32_t expireDate;
/* how many joins the link takes, zero for any number */
@property (nonatomic, readonly) int32_t usageLimit;
@property (nonatomic, readonly) int32_t usage;
@property (nonatomic, readonly) int32_t requested;
/* the link ended by its date or by its joins, and takes nobody in now */
@property (nonatomic, readonly) BOOL expired;
- (id)initWithRow:(const noshi_invite *)row;
@end

@interface NoshiSession (Invites)

/* one page of the account's own links, the live ones or the revoked ones; offsetLink is the last link of the page before and nil for the first page.
   total is how many links the chat has in that list */
- (void)loadInvitesOfDialog:(NoshiDialog *)dialog revoked:(BOOL)revoked afterInvite:(NoshiInvite *)last
                 completion:(void (^)(NSArray *invites, NSInteger total, NSString *errorName))completion;
/* a new link; zero expireDate and usageLimit leave it without that limit, and requestNeeded cannot go with a limit on joins */
- (void)createInviteInDialog:(NoshiDialog *)dialog expireDate:(int32_t)expireDate usageLimit:(int32_t)usageLimit requestNeeded:(BOOL)requestNeeded
                       title:(NSString *)title completion:(void (^)(NoshiInvite *invite, NSString *errorName))completion;
/* changes the limits, the approval switch and the name of a link; zeros take the limits off */
- (void)editInvite:(NoshiInvite *)invite inDialog:(NoshiDialog *)dialog expireDate:(int32_t)expireDate usageLimit:(int32_t)usageLimit
     requestNeeded:(BOOL)requestNeeded title:(NSString *)title completion:(void (^)(NoshiInvite *invite, NSString *errorName))completion;
/* the link stops taking people in; replacement is the link that took the place of a permanent one, nil otherwise */
- (void)revokeInvite:(NoshiInvite *)invite inDialog:(NoshiDialog *)dialog
          completion:(void (^)(NoshiInvite *revoked, NoshiInvite *replacement, NSString *errorName))completion;
/* only a revoked link can be deleted */
- (void)deleteInvite:(NoshiInvite *)invite inDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;
- (void)deleteRevokedInvitesInDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;

@end

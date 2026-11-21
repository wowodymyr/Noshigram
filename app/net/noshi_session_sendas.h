#import <Foundation/Foundation.h>

#include "noshi_messages.h"

#import "noshi_dialog.h"
#import "noshi_session.h"

/* one identity the account may write as in a chat: itself, a channel it administers, or the anonymous identity of the group */
@interface NoshiSendAsOption : NSObject {
    NoshiDialog *_identity;
    BOOL _premiumRequired;
}
/* the identity as a chat, with its name, picture and access hash */
@property (nonatomic, readonly, retain) NoshiDialog *identity;
/* the identity can only be used with Telegram Premium */
@property (nonatomic, readonly) BOOL premiumRequired;
/* the account itself */
@property (nonatomic, readonly) BOOL isAccount;
@end

/* who the account writes as in groups and channels that let it choose */
@interface NoshiSession (SendAs)

/* the person accepted the price of a paid chat: later messages to it carry the amount, and 0 takes the approval back */
- (void)approvePaidMessages:(long long)stars ofDialog:(NoshiDialog *)dialog;

/* the identities for a chat, the account itself first; a chat that offers no choice answers one option or none */
- (void)loadSendAsOptionsOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSArray *options, NSString *errorName))completion;
/* the identity messages to the chat are sent as: nil for the account itself */
- (NoshiDialog *)sendAsIdentityOfDialog:(NoshiDialog *)dialog;
/* takes the choice the server already holds (the full channel names it) without telling the server again; nil for the account itself */
- (void)adoptSendAsIdentity:(NoshiDialog *)identity ofDialog:(NoshiDialog *)dialog;
/* the person chose: later messages carry it, and the server keeps it for the other devices. nil for the account
   itself */
- (void)chooseSendAsIdentity:(NoshiDialog *)identity ofDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;

/* the stored choice for a chat, nil for the account itself; any thread */
- (NoshiDialog *)storedSendAsForChat:(const noshi_peer_ref *)chat;
- (void)storeSendAs:(NoshiDialog *)identity forChat:(const noshi_peer_ref *)chat;

@end

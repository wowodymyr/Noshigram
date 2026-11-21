#import <Foundation/Foundation.h>

#import "noshi_session.h"
#import "noshi_photo.h"

#include "noshi_privacy.h"

/* a person or a group named in an exception of a privacy rule */
@interface NoshiPrivacyEntry : NSObject {
    long long _identifier;
    BOOL _chat;
    NSString *_name;
    NoshiPhoto *_photo;
}
@property (nonatomic, readonly) long long identifier;
@property (nonatomic, readonly) BOOL chat;
@property (nonatomic, readonly, copy) NSString *name;
/* nil when the person has none, or was added on this screen and has not been read back yet */
@property (nonatomic, readonly, retain) NoshiPhoto *photo;
@end

/* who may see one piece of the account: the base (everybody, contacts, nobody) and the people and groups that are
   the exception to it */
@interface NoshiPrivacyRules : NSObject {
    noshi_privacy_key _key;
    noshi_privacy_rules *_rules;
}
- (id)initWithKey:(noshi_privacy_key)key rules:(const noshi_privacy_rules *)rules;
@property (nonatomic, readonly) noshi_privacy_key key;
@property (nonatomic, assign) noshi_privacy_base base;
/* the people, then the groups, of the list of those always allowed (allowed YES) or never allowed */
- (NSArray *)entriesAllowed:(BOOL)allowed;
- (NSUInteger)countAllowed:(BOOL)allowed;
/* NO when the list is full or the person has no hash to be named by; the person leaves the opposite list, as one
   cannot be in both */
- (BOOL)addUser:(long long)userId hash:(long long)hash name:(NSString *)name photo:(NoshiPhoto *)photo allowed:(BOOL)allowed;
/* a group by its id; NO when the list is full; the group leaves the opposite list */
- (BOOL)addChat:(long long)chatId title:(NSString *)title photo:(NoshiPhoto *)photo allowed:(BOOL)allowed;
- (void)removeEntry:(NoshiPrivacyEntry *)entry allowed:(BOOL)allowed;
- (const noshi_privacy_rules *)rules;
@end

/* posted on the main thread after a block or an unblock went through: userInfo has @"peer" (the id), @"kind" and @"blocked" */
extern NSString *const NoshiPeerBlockDidChangeNotification;

/* a person or group the account blocked */
@interface NoshiBlockedPeer : NSObject {
    noshi_blocked_row _row;
    NSString *_name;
    NoshiPhoto *_photo;
}
- (id)initWithRow:(const noshi_blocked_row *)row;
@property (nonatomic, readonly) int32_t kind;
@property (nonatomic, readonly) long long identifier;
@property (nonatomic, readonly) long long accessHash;
@property (nonatomic, readonly) int32_t date;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, retain) NoshiPhoto *photo;
@end

/* the privacy screens' calls; implemented in noshi_session_privacy.m */
@interface NoshiSession (Privacy)
- (void)loadPrivacy:(noshi_privacy_key)key completion:(void (^)(NoshiPrivacyRules *rules, NSString *errorName))completion;
/* the rules as the server holds them after the write, so the names of the exceptions are the server's */
- (void)savePrivacy:(NoshiPrivacyRules *)rules completion:(void (^)(NoshiPrivacyRules *rules, NSString *errorName))completion;
/* NoshiBlockedPeer items from the offset, and how many the account has in all */
- (void)loadBlockedFrom:(int32_t)offset completion:(void (^)(NSArray *peers, int32_t total, NSString *errorName))completion;
- (void)setBlocked:(BOOL)blocked kind:(int32_t)kind identifier:(long long)identifier hash:(long long)hash completion:(void (^)(NSString *errorName))completion;
- (void)loadAccountTTL:(void (^)(int32_t days, NSString *errorName))completion;
- (void)setAccountTTL:(int32_t)days completion:(void (^)(NSString *errorName))completion;
- (void)loadHistoryTTL:(void (^)(int32_t seconds, NSString *errorName))completion;
- (void)setHistoryTTL:(int32_t)seconds completion:(void (^)(NSString *errorName))completion;
- (void)clearPaymentsCredentials:(BOOL)credentials info:(BOOL)info completion:(void (^)(NSString *errorName))completion;
- (void)resetSavedContactsWithCompletion:(void (^)(NSString *errorName))completion;
@end

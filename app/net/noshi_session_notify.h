#import <Foundation/Foundation.h>

#import "noshi_session.h"

#include "noshi_notify.h"

/* one banner the notifier should post: the chat, the message that made it and the words */
@interface NoshiNotifyEvent : NSObject {
    int32_t _peerKind;
    long long _peerId;
    int32_t _messageId;
    NSString *_title;
    NSString *_body;
    noshi_notify_sound _sound;
    NoshiDialog *_dialog;
}
@property (nonatomic, readonly) int32_t peerKind;
@property (nonatomic, readonly) long long peerId;
@property (nonatomic, readonly) int32_t messageId;
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *body;
/* the chat as the list draws it, for the picture on the card; nil when the chat is not in the list that was read */
@property (nonatomic, retain) NoshiDialog *dialog;
/* the tone the chat asks for; kind NONE is a banner without one */
@property (nonatomic, readonly) noshi_notify_sound sound;
@end

/* what a look at the chat list needs besides the chat list: the rules of the account and the phone, and how the number on the icon is counted */
typedef struct NoshiNotifyScanOptions {
    noshi_notify_rules rules;
    BOOL badgeShown;
    BOOL badgeMuted;
    BOOL badgeMessages;
    /* the chat on screen, which stays quiet; zero for none */
    int32_t activeKind;
    long long activePeer;
} NoshiNotifyScanOptions;

typedef void (^NoshiNotifyScanCompletion)(NSArray *events, NSUInteger more, NSString *moreText, NSInteger badge, NSInteger unreadChats, NSString *errorName);

/* the chat list read for notifications; implemented in noshi_session_notify.m */
@interface NoshiSession (Notify)

/* asks the server for the newest chats and compares them with the last look, which the session keeps in a file
   beside its others; with announce off the look is only taken (the baseline), and the events come back empty */
- (void)scanNotificationsAnnouncing:(BOOL)announce options:(NoshiNotifyScanOptions)options completion:(NoshiNotifyScanCompletion)completion;

@end

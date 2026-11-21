#import <Foundation/Foundation.h>

#import "noshi_dialog.h"
#import "noshi_message.h"
#import "noshi_media_link.h"
#import "noshi_shiro.h"
#import "noshi_typing_board.h"

#include "noshi_stories.h"

typedef enum {
    NoshiAuthEventCode,
    NoshiAuthEventPassword,
    NoshiAuthEventSignUp,
    NoshiAuthEventAuthorized,
    NoshiAuthEventFailed,
    /* the account asks for a login step Noshigram does not implement, such as e-mail verification */
    NoshiAuthEventUnsupported,
    NoshiAuthEventOffline,
    /* the server dropped the session key, so the stored account is gone */
    NoshiAuthEventLoggedOut,
    /* a login token to show as a QR code; a new one follows each time the token runs out or is scanned */
    NoshiAuthEventQr,
    /* the server sent a recovery code to the e-mail of the cloud password, shown in emailPattern */
    NoshiAuthEventRecovery
} NoshiAuthEventKind;

typedef enum {
    NoshiCodeKindApp,
    NoshiCodeKindSms,
    NoshiCodeKindCall,
    NoshiCodeKindOther
} NoshiCodeKind;

/* what the login state machine reported, copied out of the transport arena */
@interface NoshiAuthEvent : NSObject {
    NoshiAuthEventKind _kind;
    NoshiCodeKind _codeKind;
    NSInteger _codeLength;
    NSInteger _resendAfter;
    NSInteger _errorNumber;
    NSString *_hint;
    BOOL _hasRecovery;
    NSString *_emailPattern;
    NSString *_errorName;
    long long _userId;
    NSString *_qrUrl;
    NSTimeInterval _qrExpires;
}
@property (nonatomic, readonly) NoshiAuthEventKind kind;
/* the tg://login address to draw as a QR code, and the unix time it stops working */
@property (nonatomic, readonly, copy) NSString *qrUrl;
@property (nonatomic, readonly) NSTimeInterval qrExpires;
@property (nonatomic, readonly) NoshiCodeKind codeKind;
/* digits the code has, zero when the server did not say */
@property (nonatomic, readonly) NSInteger codeLength;
/* seconds until the code can be sent another way, negative when it cannot */
@property (nonatomic, readonly) NSInteger resendAfter;
@property (nonatomic, readonly) NSInteger errorNumber;
@property (nonatomic, readonly, copy) NSString *hint;
/* the password has a recovery e-mail, so the code to reset it can be requested */
@property (nonatomic, readonly) BOOL hasRecovery;
/* the masked address the recovery code went to, such as a***@gmail.com */
@property (nonatomic, readonly, copy) NSString *emailPattern;
/* the rpc error name without its number, for example PHONE_CODE_INVALID or FLOOD_WAIT */
@property (nonatomic, readonly, copy) NSString *errorName;
@property (nonatomic, readonly) long long userId;
@end

@class NoshiSession;

@protocol NoshiSessionDelegate <NSObject>
/* always on the main thread */
- (void)session:(NoshiSession *)session didReceiveAuthEvent:(NoshiAuthEvent *)event;
@end

@class NoshiStickerDocument;
@class NoshiCall;
@class NoshiGroupCall;
@class NoshiGroupCallEngine;
@class NoshiCallVideo;
@class NoshiCommunity;
@class NoshiDraftBoard;

@protocol NoshiCallDelegate <NSObject>
/* the call changed, or ended; always on the main thread */
- (void)session:(NoshiSession *)session callDidChange:(NoshiCall *)call;
@end

@protocol NoshiGroupCallDelegate <NSObject>
/* the group call changed, or ended; always on the main thread */
- (void)session:(NoshiSession *)session groupCallDidChange:(NoshiGroupCall *)call;
@end

/* owns the mtproto client and one worker thread; every call below only queues work for that thread */
/* one custom emoji: the emoji it stands for, how it is stored, and the files to draw it from */
@interface NoshiCustomEmojiDocument : NSObject {
    long long _documentId;
    NSString *_alt;
    int _format;
    NoshiRemoteFile *_file;
    NoshiRemoteFile *_preview;
}
@property (nonatomic, readonly) long long documentId;
@property (nonatomic, readonly, copy) NSString *alt;
/* an noshi_sticker_format */
@property (nonatomic, readonly) int format;
@property (nonatomic, readonly, retain) NoshiRemoteFile *file;
@property (nonatomic, readonly, retain) NoshiRemoteFile *preview;
@end

/* posted on the main thread, by the session, each time connected changes */
/* posted on the main thread with the refreshed archive shortcut under the key "dialog" */
extern NSString *const NoshiArchiveSummaryDidChangeNotification;
/* the topics of some forum were read, so the forum rows of a chat list can name the topic of their last message and count what is unread in all topics */
extern NSString *const NoshiForumSummariesDidChangeNotification;
extern NSString *const NoshiSessionConnectionDidChangeNotification;
extern NSString *const NoshiSessionDialogsUpdatedNotification;
/* the other side read more of our messages in a chat; userInfo has kind, peer and maxId */
extern NSString *const NoshiReadOutboxDidChangeNotification;
/* the server took the read mark of a chat of ours (the person read it here); userInfo has kind, peer, topic, maxId and toEnd, which NoshiDialogsApplyingRead applies to a list */
extern NSString *const NoshiDialogReadNotification;
/* posted on the main thread when a message arrives live: the last-message part of its chat row twice over under the keys "user" (a private chat names nobody) and "group" (the
   sender is named), both NoshiDialog; NoshiDialogsApplyingNewMessage puts the right one into a list */
extern NSString *const NoshiNewMessageDidArriveNotification;
/* a person came online or left: userInfo has "user" (NSNumber long long), "presence" (NSNumber int) and "seen" (NSNumber int) */
extern NSString *const NoshiUserStatusDidChangeNotification;
/* the parts of a file sent in a message that the server has taken, on the main thread; userInfo has "randomId" (the NSNumber of the pending message)
   and "fraction" (an NSNumber float from 0 to 1) */
extern NSString *const NoshiUploadProgressNotification;
/* posted on the main thread after the photo or video of this account's profile was set or removed, so the screens that wear it (the tab bar) ask for the profile again */
extern NSString *const NoshiOwnProfileDidChangeNotification;

@class NoshiStoryAudience;

/* one effect of the list: the id the send request names and the emoji that stands for it */
@class NoshiCustomEmojiDocument;

@interface NoshiMessageEffect : NSObject {
    long long _effectId;
    NSString *_emoticon;
    BOOL _premium;
    NoshiCustomEmojiDocument *_animation;
    NoshiCustomEmojiDocument *_sticker;
}
@property (nonatomic, assign) long long effectId;
@property (nonatomic, copy) NSString *emoticon;
@property (nonatomic, assign) BOOL premium;
/* the lottie that plays over the chat for the effect, nil when the server sent none; the sticker of the effect plays in its place */
@property (nonatomic, retain) NoshiCustomEmojiDocument *animation;
@property (nonatomic, retain) NoshiCustomEmojiDocument *sticker;
/* an effect of the list that was loaded, by the id a message names; nil before the list is in */
+ (NoshiMessageEffect *)effectWithId:(long long)effectId;
@end

@interface NoshiSession : NSObject {
    id<NoshiSessionDelegate> _delegate;
    id<NoshiCallDelegate> _callDelegate;
    id<NoshiGroupCallDelegate> _groupCallDelegate;
    /* who the account writes as in each chat that offers a choice, as the noshi_peer_ref data of the identity, keyed by the chat; any thread, under @synchronized */
    NSMutableDictionary *_sendAsChoices;
    NSArray *_chatFolders;
    NSUInteger _chatFolderGeneration;
    uint64_t _folderFloodUntilMs;
    BOOL _chatFolderSaving;
    NoshiDraftBoard *_drafts;
    /* worker only: every draft of the account was asked for in this run */
    BOOL _draftsRequested;
}

@property (nonatomic, assign) id<NoshiSessionDelegate> delegate;
/* main thread only: hears every change of the one voice call the session can hold */
@property (nonatomic, assign) id<NoshiCallDelegate> callDelegate;
/* main thread only: hears every change of the one group call (voice chat) the session can hold */
@property (nonatomic, assign) id<NoshiGroupCallDelegate> groupCallDelegate;
/* the voice chats of the account: joining, making and leaving them */
@property (nonatomic, readonly) NoshiGroupCallEngine *groupCalls;
/* main thread only: who is typing in which chat, from the live updates */
@property (nonatomic, readonly) NoshiTypingBoard *typing;
- (void)setTyping:(BOOL)typing inDialog:(NoshiDialog *)dialog;
/* main thread only: the drafts of the account's chats, from the chat lists, the live updates and what the person types */
@property (nonatomic, readonly) NoshiDraftBoard *drafts;
/* the newest id of ours the other side is known to have read in a chat since the app started, zero when no update said; main thread */
/* topic is 0 for the read mark of a whole chat, and the id of the topic for one topic of a forum */
- (int32_t)readOutboxOfKind:(int32_t)kind peer:(long long)peer topic:(int32_t)topic;
- (void)noteReadOutbox:(int32_t)maxId ofKind:(int32_t)kind peer:(long long)peer topic:(int32_t)topic;
/* main thread only: the messages of a chat whose send failed, kept while its screen is closed so they are there, with their files, when the chat is opened again; they are held
   until the person sends them again or deletes them, and are lost with the app */
- (void)keepUnsentMessage:(NoshiMessage *)message forDialog:(NoshiDialog *)dialog;
/* hands them over: the session forgets them, and the screen that takes them is the one that keeps them from then on */
- (NSArray *)takeUnsentMessagesForDialog:(NoshiDialog *)dialog;
/* main thread only: whether the link is up and the server has answered on it since it was opened; screens show
   a connecting title while it is NO */
@property (nonatomic, readonly) BOOL connected;
/* any thread: whether the last link was opened through the Shiro tunnel. a stream of the tunnel is a local socket pair, which the system cannot keep alive for the
   network, so ios 5 and 6 let the app sleep with nothing to wake it unless the notifier plays its silence */
@property (atomic, readonly) BOOL tunneled;

/* directory holds the session keys, the account file and the database; it is created when missing */
- (id)initWithDirectory:(NSString *)directory;
+ (BOOL)hasAccountInDirectory:(NSString *)directory;
/* the id of the stored account, zero when there is none; read from the account file, so any thread may ask */
+ (long long)accountIdInDirectory:(NSString *)directory;
/* where the keys, the account file, the database and the other files of the account are kept */
@property (nonatomic, readonly, copy) NSString *directory;

/* the VPN the connections go through when it is wanted; set before start */
@property (nonatomic, assign) NoshiShiro *shiro;

- (void)start;
- (void)stop;
/* the network came back or the user retried after an offline event */
- (void)reconnect;
/* how long a quiet link waits before it pings the server, in milliseconds (the client keeps it between 10 and 300
   seconds, 0 is its default of 30) */
- (void)setPingInterval:(uint32_t)milliseconds;
/* runs the block on the main thread once the session thread has finished what it was doing and what was posted
   before this call, which is when its transaction on the database, if one was open */
- (void)afterPendingWork:(void (^)(void))block;
/* the route of the traffic changed (the VPN went up, dropped or was switched): the open links are on the old path, so they are closed and opened
   again on the new one */
- (void)routeChanged;

- (void)requestCodeForNumber:(NSString *)number;
- (void)submitCode:(NSString *)code;
- (void)resendCode;
/* asks for a login token to show as a QR code; the answers are NoshiAuthEventQr events, then the usual ones once another device
   confirmed (a password, or authorized) */
- (void)requestQrLogin;
- (void)submitPassword:(NSString *)password;
/* asks for a code on the recovery e-mail; the answer is an NoshiAuthEventRecovery event, or a failure that keeps the password screen */
- (void)requestPasswordRecovery;
/* the code from the recovery e-mail; a right one signs in and drops the cloud password */
- (void)submitRecoveryCode:(NSString *)code;
- (void)submitFirstName:(NSString *)first lastName:(NSString *)last;
- (void)cancelLogin;

/* every load below runs its completion on the main thread, with the items in server order or with nil and the rpc
   error name */
typedef void (^NoshiListCompletion)(NSArray *items, NSString *errorName);

- (void)loadDialogs:(NoshiListCompletion)completion;
/* folder 0 is the main list, 1 the archive; the main list carries the archive as its own entry */
- (void)loadDialogsInFolder:(int32_t)folder completion:(NoshiListCompletion)completion;
/* the chats of the main list beyond the first request, for a search that has to see every chat and not the hundred the list keeps; known is what the screen already holds, and the answer is
   known followed by the chats that were not in it. A page that fails ends the walk with what came so far. */
- (void)loadRemainingDialogsAfter:(NSArray *)known completion:(void (^)(NSArray *all))completion;
/* whether the last answer for the main list was a slice, so chats are left beyond the first request */
- (BOOL)mainListHasMore;
- (void)loadDialogPageInFolder:(int32_t)folder after:(NoshiDialog *)cursor completion:(void (^)(NSArray *items, NoshiDialog *next, NSString *errorName))completion;
/* the list as the last good load left it, so a screen can show it before the network answers; a nil list means
   nothing is kept yet and is not an error */
- (void)loadCachedDialogsInFolder:(int32_t)folder completion:(NoshiListCompletion)completion;
/* moves a chat into the archive (folder 1) or back to the main list (0) on the server; the completion
   runs on the main thread with nil on success or the rpc error name */
- (void)moveDialog:(NoshiDialog *)dialog toFolder:(int32_t)folder completion:(void (^)(NSString *errorName))completion;
/* makes a channel, or a supergroup when megagroup is set, with the title; the completion runs on the main thread with nil on
   success or the rpc error name */
- (void)createChannelTitled:(NSString *)title megagroup:(BOOL)megagroup completion:(void (^)(NSString *errorName))completion;
/* every public user, bot, group and channel whose name or @username starts with the text, as NoshiDialog items:
   the chats the account has first */
- (void)searchPeers:(NSString *)query completion:(NoshiListCompletion)completion;
- (void)loadContacts:(NoshiListCompletion)completion;
/* the signed in user as a one item list */
- (void)loadSelf:(NoshiListCompletion)completion;
/* the account's own profile as it was last read, in memory or from the file the last run left, nil on a first
   start */
- (NoshiPerson *)ownPerson;

/* a file, wherever it lives; the completion runs on the main thread with the bytes, or nil and an error name
   (TIMEOUT, FILE_TOO_BIG, an rpc error name) */
- (void)downloadFile:(NoshiRemoteFile *)file completion:(NoshiDownloadCompletion)completion;
/* one part of a large file: up to limit bytes from offset, fewer on the last part and none past the end */
- (void)downloadFile:(NoshiRemoteFile *)file offset:(long long)offset limit:(int32_t)limit completion:(NoshiDownloadCompletion)completion;

/* voice and video calls: one at a time */
- (void)startCallToDialog:(NoshiDialog *)dialog;
- (void)startVideoCallToDialog:(NoshiDialog *)dialog;
- (void)acceptCall;
- (void)declineCall;
- (void)hangUpCall;
- (void)setCallMuted:(BOOL)muted;
/* the camera of a call that runs; a device without one, or a refusal, leaves the call as an audio call and the
   snapshot says so */
- (void)setCallCameraOn:(BOOL)on;
/* main thread: the camera and the pictures of the call that runs, nil when none does; valid while the call lasts */
- (NoshiCallVideo *)activeCallVideo;

/* ends the session on the server, then drops the key and the stored account; NoshiAuthEventLoggedOut follows */
- (void)signOut:(void (^)(NSString *errorName))completion;

/* the device model, system version and app version the server lists for this session in the devices screen, until the app restarts. the server has them
   with the next request, which this sends; nil for all three goes back to what the device really is. the completion runs on the main thread with the name
   of the failure or nil: DEVICE_INVALID for a model or system version that is empty or longer than 128 bytes, or an error of the request */
- (void)setDeviceModel:(NSString *)model systemVersion:(NSString *)system appVersion:(NSString *)app completion:(void (^)(NSString *errorName))completion;

@end

/* the answers of the chat calls, on the main thread */
typedef void (^NoshiHistoryCompletion)(NSArray *messages, NSDictionary *people, NSString *errorName);
typedef void (^NoshiHistoryPageCompletion)(NSArray *messages, NSDictionary *people, noshi_history_page page, NSString *errorName);
typedef void (^NoshiSendCompletion)(int32_t messageId, NSString *errorName);
typedef void (^NoshiSearchCompletion)(NSArray *dialogs, int32_t nextRate, NSString *errorName);

/* chats: history, sending, live messages and stickers; implemented in noshi_session_chat.m */
@interface NoshiSession (Chat)
- (void)uploadStickerAtPath:(NSString *)path completion:(void (^)(NoshiStickerDocument *document, NSString *errorName))completion;

/* the newest messages of a chat, or the ones before beforeId (zero for the newest), newest first, with the people
   they mention keyed by user id (NSNumber) as NoshiPerson */
- (void)loadHistoryOfDialog:(NoshiDialog *)dialog beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(NoshiHistoryCompletion)completion;
/* a page that may reach toward newer messages: offsetId and a negative addOffset as noshi_history_window_request takes them */
- (void)loadHistoryOfDialog:(NoshiDialog *)dialog offsetId:(int32_t)offsetId addOffset:(int32_t)addOffset limit:(int32_t)limit completion:(NoshiHistoryCompletion)completion;
- (void)loadHistoryOfDialog:(NoshiDialog *)dialog offsetId:(int32_t)offsetId addOffset:(int32_t)addOffset limit:(int32_t)limit pageCompletion:(NoshiHistoryPageCompletion)completion;

/* the topics of a forum as NoshiDialog items carrying a topicId, pinned ones first and then by last message; at
   most 200 */
- (void)loadTopicsOfDialog:(NoshiDialog *)forum completion:(NoshiListCompletion)completion;
/* gives the forums of a list the summary kept for them; the list is then complete as far as it is known */
- (void)applyForumSummariesToDialogs:(NSArray *)dialogs;
/* the number of messages in a topic, or in the chat when topicId is zero */
- (void)loadMessageCountOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSInteger count, NSString *errorName))completion;
/* the favorites split by the chat each message came from, newest first: NoshiDialog rows, the one for the account's own notes included (its saved is set) */
- (void)loadSavedDialogs:(NoshiListCompletion)completion;

/* the chats a community groups, from the server */
- (void)loadCommunity:(NoshiDialog *)community knownDialogs:(NSArray *)known completion:(void (^)(NoshiCommunity *community, NSString *errorName))completion;
/* shows the community as one chat in the list, or as its separate chats; the completion runs on the main thread with nil on success or the rpc error name */
- (void)setCommunity:(NoshiDialog *)community collapsed:(BOOL)collapsed completion:(void (^)(NSString *errorName))completion;

/* the pinned messages of a chat, newest first, up to a hundred, with the people they mention keyed as for the
   history */
- (void)loadPinnedMessagesOfDialog:(NoshiDialog *)dialog completion:(NoshiHistoryCompletion)completion;
/* the messages of the person that got a reaction not seen yet, newest first */
- (void)loadUnreadReactionsOfDialog:(NoshiDialog *)dialog completion:(NoshiHistoryCompletion)completion;
/* explicit is a tap of the person, which ghost mode lets through; the read that comes of scrolling is automatic and stays unsent in it. NO when nothing was sent */
- (BOOL)markReactionsReadOfDialog:(NoshiDialog *)dialog explicit:(BOOL)explicit;
/* the messages of a chat that contain a text, newest first; the query is not empty and at most NOSHI_CHAT_SEARCH_QUERY_MAX bytes of UTF-8 */
- (void)searchMessagesOfDialog:(NoshiDialog *)dialog query:(NSString *)query completion:(NoshiHistoryCompletion)completion;
/* everything one person wrote in the chat, newest first, as the "history" of the menu of a message in a group */
- (void)searchMessagesOfDialog:(NoshiDialog *)dialog fromUserId:(long long)userId accessHash:(long long)accessHash completion:(NoshiHistoryCompletion)completion;
/* everything the account itself wrote in the chat, newest first */
/* the photos and videos, the files or the links of a chat, newest first, a page older than beforeId (zero for the newest) */
- (void)loadSharedOfDialog:(NoshiDialog *)dialog kind:(noshi_shared_kind)kind beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(NoshiHistoryCompletion)completion;
/* the messages the account itself wrote in the chat (in its topic when the dialog is one), newest first, a page of limit older than beforeId (zero for the newest) */
- (void)loadOwnMessagesOfDialog:(NoshiDialog *)dialog beforeId:(int32_t)beforeId limit:(int32_t)limit completion:(NoshiHistoryCompletion)completion;
/* the oldest message of a kind in the chat, as a page of one */
- (void)loadOldestSharedOfDialog:(NoshiDialog *)dialog kind:(noshi_shared_kind)kind completion:(NoshiHistoryCompletion)completion;
/* the oldest messages of the chat, one page, newest of them first */

/* the newest messages of a chat that earlier loads and live updates left on disk, with their senders; nil messages
   when none are kept */
- (void)loadCachedHistoryOfDialog:(NoshiDialog *)dialog completion:(NoshiHistoryCompletion)completion;

/* sends a message; randomId names it on the way back and must differ for every message */
/* entities are the NoshiTextEntity items of the text; only the custom emoji among them travel with it, and nil sends plain text */
- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId completion:(NoshiSendCompletion)completion;
/* the same as an answer to the message replyTo; zero sends it on its own */
- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(NoshiSendCompletion)completion;
/* an answer that quotes words of the message it answers */
- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo quote:(NSString *)quote quoteOffset:(int32_t)quoteOffset completion:(NoshiSendCompletion)completion;
/* silent sets the silent flag, so the people of the chat get no sound */
- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo quote:(NSString *)quote quoteOffset:(int32_t)quoteOffset silent:(BOOL)silent completion:(NoshiSendCompletion)completion;
/* the same with an effect (zero for none) */
- (void)sendText:(NSString *)text entities:(NSArray *)entities toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo quote:(NSString *)quote quoteOffset:(int32_t)quoteOffset silent:(BOOL)silent effect:(long long)effect completion:(NoshiSendCompletion)completion;
/* the effects a message of a private chat can go with, as NoshiMessageEffect items in the order of the server; asked once and kept for the session */
- (void)loadMessageEffects:(void (^)(NSArray *effects, NSString *errorName))completion;
- (void)sendSticker:(NoshiMedia *)sticker toDialog:(NoshiDialog *)dialog randomId:(long long)randomId completion:(NoshiSendCompletion)completion;
/* sends a recorded file as a voice note or a round video: the file goes up in parts, then the message names it */
- (void)sendVoiceAtPath:(NSString *)path durationMs:(int32_t)durationMs waveform:(NSData *)waveform toDialog:(NoshiDialog *)dialog
               randomId:(long long)randomId completion:(NoshiSendCompletion)completion;
- (void)sendRoundVideoAtPath:(NSString *)path durationMs:(int32_t)durationMs side:(int32_t)side toDialog:(NoshiDialog *)dialog
                    randomId:(long long)randomId completion:(NoshiSendCompletion)completion;
/* a jpeg as a photo, an mp4 as a video, any file as a document with its name and mime type, a point on the map; the same
   completion and error names as the recordings */
- (void)sendOutgoing:(NoshiOutgoing *)outgoing toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(NoshiSendCompletion)completion;
- (void)sendSticker:(NoshiMedia *)sticker toDialog:(NoshiDialog *)dialog randomId:(long long)randomId replyTo:(int32_t)replyTo completion:(NoshiSendCompletion)completion;
- (void)sendPhotoAtPath:(NSString *)path caption:(NSString *)caption spoiler:(BOOL)spoiler toDialog:(NoshiDialog *)dialog randomId:(long long)randomId completion:(NoshiSendCompletion)completion;
- (void)sendVideoAtPath:(NSString *)path durationMs:(int32_t)durationMs width:(int32_t)width height:(int32_t)height caption:(NSString *)caption spoiler:(BOOL)spoiler toDialog:(NoshiDialog *)dialog
               randomId:(long long)randomId completion:(NoshiSendCompletion)completion;
- (void)sendDocumentAtPath:(NSString *)path name:(NSString *)name mime:(NSString *)mime caption:(NSString *)caption toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
                completion:(NoshiSendCompletion)completion;
/* two to ten photos and videos as one album; each is uploaded, then one request sends them together, so the other
   side sees one collage. randomIds are the NSNumber random ids of the pending messages, one for each item in order */
- (void)sendAlbumOfOutgoings:(NSArray *)outgoings toDialog:(NoshiDialog *)dialog randomIds:(NSArray *)randomIds completion:(void (^)(NSArray *messageIds, NSString *errorName))completion;
/* stops the upload of the pending message with this random id; the completion of its send then reports CANCELLED. A message the server
   already has is not recalled */
- (void)cancelSendWithRandomId:(long long)randomId;
- (void)sendLocationLatitude:(double)latitude longitude:(double)longitude toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
                  completion:(NoshiSendCompletion)completion;
/* a jpeg becomes the profile photo of the signed in user: the file goes up in parts, then the server is told to
   use it */
- (void)uploadProfilePhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion;
/* a jpeg becomes the public photo: it is shown to those who are not allowed to see the main profile photo, and the main photo is left as it is */
- (void)uploadPublicPhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion;
/* a jpeg becomes the photo of a contact: set for them on this account's side, or with suggest sent to them as a proposal for their own profile photo */
- (void)uploadContactPhotoAtPath:(NSString *)path ofPerson:(NoshiPerson *)person suggest:(BOOL)suggest completion:(void (^)(NSString *errorName))completion;
/* the same for an mp4 that becomes a moving profile picture: square, ten seconds at most and small, as NoshiProfilePhotoPicker makes it */
- (void)uploadProfileVideoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion;
/* a jpeg becomes a story of the signed in user, shown to everyone for a day, no caption; the completion is the same as the profile photo's */
- (void)postStoryPhotoAtPath:(NSString *)path completion:(void (^)(NSString *errorName))completion;
/* the same with a caption (at most 200 characters, nil for none) and the audience that sees it */
- (void)postStoryPhotoAtPath:(NSString *)path caption:(NSString *)caption privacy:(noshi_story_privacy)privacy completion:(void (^)(NSString *errorName))completion;
- (void)postStoryPhotoAtPath:(NSString *)path caption:(NSString *)caption audience:(NoshiStoryAudience *)audience completion:(void (^)(NSString *errorName))completion;
/* the custom emoji documents with the ordinary emoji each stands for and the files that draw it, as
   NoshiCustomEmojiDocument items; a document the server does not know is missing */
- (void)loadCustomEmojiDocuments:(NSArray *)documentIds completion:(void (^)(NSArray *documents, NSString *errorName))completion;
/* ordinary emoji choices permitted by this chat, as NoshiReaction items */
/* a Premium account is also offered the custom emoji the chat allows: those it lists, and where it allows any, the account's favorites */
- (void)loadAvailableReactionsForDialog:(NoshiDialog *)dialog premium:(BOOL)premium completion:(NoshiListCompletion)completion;
/* the same list, with whether the chat takes any custom emoji as a reaction (the picker offers its emoji panel only then) */
typedef void (^NoshiReactionChoicesCompletion)(NSArray *choices, BOOL customAllowed, NSString *errorName);
- (void)loadReactionChoicesForDialog:(NoshiDialog *)dialog premium:(BOOL)premium completion:(NoshiReactionChoicesCompletion)completion;
/* returns the updated stored messages for these ids, including history outside the watched page */
- (void)refreshReactionsForMessages:(NSArray *)ids dialog:(NoshiDialog *)dialog completion:(NoshiListCompletion)completion;
/* stars sent to a message as a reaction; the reactions of the message come back as they are after it */
- (void)sendPaidReactionOfStars:(int32_t)stars messageId:(int32_t)messageId dialog:(NoshiDialog *)dialog completion:(NoshiListCompletion)completion;
/* the pictures the server draws every ordinary reaction with, as NoshiReactionArtwork items; nil with an error name when the call or the answer failed */
- (void)loadReactionArt:(NoshiListCompletion)completion;
/* how many ordinary reactions one account may leave on a message, from help.getAppConfig; the error name is nil when the server's own numbers
   arrived, and the documented 1 and 3 stand in otherwise */
- (void)loadReactionLimits:(void (^)(int32_t standard, int32_t premium, NSString *errorName))completion;
- (void)sendReactions:(NSArray *)reactions messageId:(int32_t)messageId dialog:(NoshiDialog *)dialog
           completion:(NoshiListCompletion)completion;
/* tells the server everything up to maxId is read. toEnd says the person has seen the end of the chat, so nothing newer than maxId is unread. when the server has taken it the
   NoshiDialogReadNotification goes out, so the lists clear their counts at once, and completion runs on the main thread with nil, or with the error that stopped it */
- (void)markDialogRead:(NoshiDialog *)dialog upTo:(int32_t)maxId toEnd:(BOOL)toEnd completion:(void (^)(NSString *errorName))completion;
- (void)markMentionsRead:(NSArray *)ids dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;
/* messages.readMessageContents: the voice notes, round videos and one-time media of these messages count as played or opened; the ids are NSNumbers */
- (void)markContentsRead:(NSArray *)ids dialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;

/* pin, mute or delete one chat on the server; the completion runs on the main thread with nil on success or the
   rpc error name */
typedef enum { NoshiChatCommandPin, NoshiChatCommandUnpin, NoshiChatCommandMute, NoshiChatCommandUnmute,
               NoshiChatCommandDelete, NoshiChatCommandClear,
               /* the swipe of the chat list: everything read (messages.readHistory), the manual "unread" mark put on, and that mark taken off */
               NoshiChatCommandMarkRead, NoshiChatCommandMarkUnread, NoshiChatCommandClearUnreadMark } NoshiChatCommand;
- (void)performAction:(NoshiChatCommand)action onDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *errorName))completion;
/* reads every unread chat of a folder, one after the other so the server is not asked for them all at once; the completion runs on the main thread with nil
   when all were read, or the first error name, after which the rest are left as they were */
- (void)markAllReadInFolder:(int32_t)folderId completion:(void (^)(NSString *errorName))completion;

/* a search through every chat for the text: one NoshiDialog per found message, naming the chat, with the found
   message as its last one, and the offset for the next page (zero when there is none) */
- (void)searchGlobal:(NSString *)query kind:(noshi_search_kind)kind offsetRate:(int32_t)offsetRate completion:(NoshiSearchCompletion)completion;

/* the handler runs on the main thread with the newest stored messages of the chat, newest first, each time the
   store changed in a way that touches them; nil for dialog stops watching */
- (void)watchDialog:(NoshiDialog *)dialog handler:(void (^)(NSArray *messages))handler;
/* includes the stored identities of the current page, keyed like NoshiMessage.senderKey */
- (void)watchDialog:(NoshiDialog *)dialog peopleHandler:(void (^)(NSArray *messages, NSDictionary *people))handler;
/* the same for a screen that has to be able to stop only its own watch: the screens of a theme change overlap for a moment, and the one going must not stop the one
   that came */
- (void)watchDialog:(NoshiDialog *)dialog owner:(id)owner peopleHandler:(void (^)(NSArray *messages, NSDictionary *people))handler;
- (void)stopWatchingForOwner:(id)owner;
/* group roles and the users named by the answer, delivered on the main thread */
- (void)loadSenderRolesOfDialog:(NoshiDialog *)dialog completion:(void (^)(NSDictionary *roles, NSDictionary *people, NSString *errorName))completion;
/* known users from the local store, indexed by their ids */
- (void)loadCachedPeopleWithIds:(NSArray *)ids completion:(void (^)(NSDictionary *people))completion;
/* a sender channel seen only as a min object, resolved through the message that named it */
- (void)loadChannelSender:(long long)channelId ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog
               completion:(void (^)(NoshiPerson *person, NSString *errorName))completion;

/* NoshiStickerSet items of the installed sets, NoshiSticker items of one set, and of the recently used ones */
- (void)loadStickerSets:(NoshiListCompletion)completion;
- (void)loadAnimatedEmojiStickers:(NoshiListCompletion)completion;
/* the animations of one game emoji in set order, as NoshiSticker; the one at index n is the throw that ends on the result n, and the first loops while the result is unknown.
   a document that cannot be used keeps its index with a sticker that has no file */
- (void)loadDiceStickersForEmoji:(NSString *)emoji completion:(NoshiListCompletion)completion;
- (void)loadStickersOfSet:(NoshiStickerSet *)set completion:(NoshiListCompletion)completion;
/* the stickers of a set the server names by its short name, in set order, whether or not the person has installed it */
- (void)loadStickersOfSetNamed:(NSString *)shortName completion:(NoshiListCompletion)completion;
/* the custom emoji sets the person has installed as NoshiStickerSet items, and the NoshiCustomEmojiDocument items of one */
- (void)loadEmojiSets:(NoshiListCompletion)completion;
- (void)loadEmojiOfSet:(NoshiStickerSet *)set completion:(NoshiListCompletion)completion;
- (void)loadRecentStickers:(NoshiListCompletion)completion;
/* the stickers the person marked as favorites, and the animations they kept (NoshiSticker items whose media is a GIF), newest first */
- (void)loadFavedStickers:(NoshiListCompletion)completion;
- (void)loadSavedGifs:(NoshiListCompletion)completion;
/* puts a sticker among the favorites or takes it out; the completion gets nil once the server took it */
- (void)faveSticker:(NoshiSticker *)sticker unfave:(BOOL)unfave completion:(void (^)(NSString *errorName))completion;
/* empties the list of the stickers used lately */
- (void)clearRecentStickers:(void (^)(NSString *errorName))completion;
/* NoshiSticker items the server suggests for a waving hand, the greetings an empty chat offers */
- (void)loadGreetingStickers:(NoshiListCompletion)completion;
/* stickers that match one emoticon, a static C string such as the waving hand */
- (void)loadStickersWithEmoticon:(const char *)emoticon completion:(NoshiListCompletion)completion;

@end

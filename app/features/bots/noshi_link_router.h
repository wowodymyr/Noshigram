#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_sticker_library.h"
#import "noshi_session.h"
#import "noshi_session_bots.h"

/* what a tap on an address, a @name, a command or a button of a bot leads to: a chat, an invoice or the system's
   browser */
/* posted with userInfo {url: NSString} for an address that came from outside the screens, such as a tg:// link the
   system handed to the app; the main screen routes it through its own router */
extern NSString *const NoshiOpenLinkNotification;

/* whether the app opens this address itself: the tg scheme and the t.me, telegram.me and telegram.dog hosts over http or https */
BOOL NoshiIsTelegramLink(NSURL *url);

@interface NoshiLinkRouter : NSObject {
    NoshiSession *_session;
    NoshiAvatarCache *_avatars;
    NoshiMediaCache *_media;
    NoshiStickerLibrary *_stickers;
    UIViewController *_anchor;
    NSUInteger _token;
}

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
             stickers:(NoshiStickerLibrary *)stickers;

@property (nonatomic, assign) UIViewController *anchor;
@property (nonatomic, readonly) NoshiSession *session;

/* any address a person can tap: t.me links and tg:// links open inside the app, everything else goes to the system; the links of a
   bot's web app open the chat with the bot */
- (void)openLink:(NSString *)url;
/* pushes the chat of a dialog; draft fills its field and startParam starts a bot with that parameter */
- (void)openDialog:(NoshiDialog *)dialog person:(NoshiPerson *)person draft:(NSString *)draft startParam:(NSString *)startParam;
/* the same, and the chat opens at the message with this number, zero for the usual place */
- (void)openDialog:(NoshiDialog *)dialog person:(NoshiPerson *)person draft:(NSString *)draft startParam:(NSString *)startParam messageId:(int32_t)messageId;
/* the profile of a user a message names; asks the server for the hash that opening it needs */
- (void)openProfileOfUser:(long long)userId inMessage:(int32_t)messageId dialog:(NoshiDialog *)dialog;
/* lets the person pick chats the filter accepts, up to limit of them; the completion gets the ticked ones, cancelled (may be nil) runs instead when they back out
   or when there is no screen to show the picker on */
- (void)pickDialogsWithFilter:(BOOL (^)(NoshiDialog *dialog))filter limit:(NSUInteger)limit completion:(void (^)(NSArray *dialogs))completion cancelled:(void (^)(void))cancelled;
/* lets the person pick one of their chats whose kind is in the mask (bit 0 people, 1 bots, 2 groups, 3 channels, zero for any) and tells
   the completion; nil if they backed out */
- (void)pickDialogWithTypes:(uint8_t)types completion:(void (^)(NoshiDialog *dialog))completion;
/* asks the person to pay an invoice in stars; the completion gets paid, cancelled or failed */
- (void)payInvoiceOfSlug:(NSString *)slug completion:(void (^)(NSString *status))completion;
- (void)payInvoiceOfMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog completion:(void (^)(NSString *status))completion;
/* a short text on the screen for something that is not worth an alert */
- (void)showNote:(NSString *)text;
/* the readable form of an error name from the bot calls */
+ (NSString *)textForError:(NSString *)errorName;

@end

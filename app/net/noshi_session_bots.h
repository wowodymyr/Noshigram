#import <Foundation/Foundation.h>

#import "noshi_bot.h"
#import "noshi_session.h"

@class NoshiRemoteFile;

/* the answers of the bot calls; every completion runs on the main thread */
typedef void (^NoshiResolveCompletion)(NoshiDialog *dialog, NoshiPerson *person, NSString *errorName);
typedef void (^NoshiCallbackCompletion)(NoshiCallbackAnswer *answer, NSString *errorName);

/* bots: their buttons, commands and inline mode; implemented in noshi_session_bots.m */
@interface NoshiSession (Bots)

/* the user, bot, group or channel behind @name (without the @) */
- (void)resolveUsername:(NSString *)name completion:(NoshiResolveCompletion)completion;
/* the inline bots the signed in person used most lately, the most used first, as NoshiPerson items; only bots with a public name */
- (void)loadRecentInlineBots:(void (^)(NSArray *bots, NSString *errorName))completion;
/* the person this account already has under the user id, with the photo the chats gave it, nil when it has none; the completion runs on the main thread. the id is
   what stays when a username changes */
- (void)loadStoredPersonOfUserId:(long long)userId completion:(void (^)(NoshiPerson *person))completion;
/* an invite link to a private group or channel (the hash of t.me/+hash): what it leads to without joining, and the join itself.
   member is set when the account is in the chat already, and then the chat opens as it is */
typedef void (^NoshiInviteCheckCompletion)(NoshiDialog *member, NSString *title, NSString *about, NoshiRemoteFile *photo, NSInteger participants, BOOL broadcast, BOOL requestNeeded, long long subscriptionStars, NSString *errorName);
- (void)checkInviteHash:(NSString *)hash completion:(NoshiInviteCheckCompletion)completion;
- (void)joinInviteHash:(NSString *)hash completion:(void (^)(NoshiDialog *dialog, NSString *errorName))completion;
/* stores the name the person gives a user (contacts.addContact), which the server shows instead of the user's own;
   the last name may be empty */
/* adds somebody by the number of their phone (contacts.importContacts) with the name the person gives; found says
   whether the number has an account */
- (void)addContactPhone:(NSString *)phone firstName:(NSString *)first lastName:(NSString *)last completion:(void (^)(BOOL found, NSString *errorName))completion;
- (void)editContact:(NoshiPerson *)person firstName:(NSString *)first lastName:(NSString *)last completion:(void (^)(NSString *errorName))completion;
/* the private note under the username of a contact (contacts.updateContactNote); an empty note takes it off */
- (void)setContactNote:(NSString *)note ofPerson:(NoshiPerson *)person completion:(void (^)(NSString *errorName))completion;
/* takes the photo the person set for this contact away, so the contact's own photo shows again */
- (void)resetContactPhotoOfPerson:(NoshiPerson *)person completion:(void (^)(NSString *errorName))completion;
/* what the bot says in its empty chat and its menu; a user without bot info answers an empty info */
- (void)loadBotInfoOfPerson:(NoshiPerson *)bot completion:(void (^)(NoshiBotInfo *info, NSString *errorName))completion;
/* the first message of a chat with a bot; param is the start parameter, empty for none */
- (void)startBot:(NoshiPerson *)bot inDialog:(NoshiDialog *)dialog param:(NSString *)param randomId:(long long)randomId
      completion:(NoshiSendCompletion)completion;

/* the press of a callback or game button of the message. password is the account password for a button that asks
   for it, nil otherwise */
- (void)pressButton:(NoshiMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog password:(NSString *)password
         completion:(NoshiCallbackCompletion)completion;

/* @bot query typed in a chat; offset is empty for the first page and the page's nextOffset for the next */
- (void)searchInline:(NSString *)query bot:(NoshiPerson *)bot inDialog:(NoshiDialog *)dialog offset:(NSString *)offset
          completion:(void (^)(NoshiInlinePage *page, NSString *errorName))completion;
- (void)searchInline:(NSString *)query bot:(NoshiPerson *)bot inDialog:(NoshiDialog *)dialog offset:(NSString *)offset
           location:(noshi_geo_point)point completion:(void (^)(NoshiInlinePage *page, NSString *errorName))completion;
- (void)loadVenueSearchBot:(void (^)(NoshiPerson *bot, NSString *errorName))completion;
- (void)searchVenues:(NSString *)query latitude:(double)latitude longitude:(double)longitude bot:(NoshiPerson *)bot
           inDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiInlinePage *page, NSString *errorName))completion;
- (void)sendInlineResult:(NoshiInlineResult *)result queryId:(long long)queryId toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
              completion:(NoshiSendCompletion)completion;
- (void)sendInlineResult:(NoshiInlineResult *)result queryId:(long long)queryId toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
              replyTo:(int32_t)replyTo completion:(NoshiSendCompletion)completion;
/* a picture a bot hosts behind the servers; one it hosts itself is fetched by its address */
- (void)loadWebFile:(NoshiWebFile *)file completion:(void (^)(NSData *data, NSString *errorName))completion;

/* the user a message names, with the access hash their profile needs */
- (void)loadUser:(long long)userId ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiPerson *person, NSString *errorName))completion;

/* signing in on a site: first the question for a button of a message or a bare address, then the answer */
- (void)requestUrlAuthForButton:(NoshiMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog
                     completion:(void (^)(NoshiUrlAuth *auth, NSString *errorName))completion;
- (void)requestUrlAuthForUrl:(NSString *)url completion:(void (^)(NoshiUrlAuth *auth, NSString *errorName))completion;
- (void)acceptUrlAuth:(NoshiUrlAuth *)auth button:(NoshiMarkupButton *)button ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog
         writeAllowed:(BOOL)writeAllowed code:(NSString *)code completion:(void (^)(NoshiUrlAuth *result, NSString *errorName))completion;

/* an invoice in stars: the server's form for the invoice of a message or of a link slug, then the payment */
- (void)loadStarsInvoiceOfMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog completion:(void (^)(NoshiStarsInvoice *invoice, NSString *errorName))completion;
- (void)loadStarsInvoiceOfSlug:(NSString *)slug completion:(void (^)(NoshiStarsInvoice *invoice, NSString *errorName))completion;
- (void)payStarsInvoice:(NoshiStarsInvoice *)invoice completion:(void (^)(NSString *errorName))completion;

/* the person's own number as a contact, for a keyboard button that asks for it */
- (void)sendContactPhone:(NSString *)phone name:(NSString *)name toDialog:(NoshiDialog *)dialog randomId:(long long)randomId
              completion:(NoshiSendCompletion)completion;
/* the chats picked for a request peer button of the message */
- (void)sendRequestedDialogs:(NSArray *)dialogs buttonId:(int32_t)buttonId ofMessage:(int32_t)messageId inDialog:(NoshiDialog *)dialog
                  completion:(void (^)(NSString *errorName))completion;

@end

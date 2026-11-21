#import "noshi_settings_kit.h"
#import "noshi_session.h"

@class NoshiMediaCache;
@class NoshiAvatarCache;

/* the picture a list row shows for a reaction: the emoji, or the custom emoji once its document is loaded; nil while it is not */
UIImage *NoshiReactionRowImage(NoshiReaction *reaction);
/* asks for the documents of the custom reactions among the items (dictionaries with a @"reaction"), remembers the emoji they stand for, and then runs done */
void NoshiLoadReactionDocuments(NSArray *items, NoshiSession *session, NoshiMediaCache *media, void (^done)(void));

@interface NoshiReactionPeopleController : NoshiSettingsPageController
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog messageId:(int32_t)messageId avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
@end

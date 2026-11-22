#import <UIKit/UIKit.h>

#import "noshi_avatar_cache.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_sticker_library.h"

/* the contact list as a system table with a search bar; a contact opens into its chat */
@interface NoshiClassicContactsController : UITableViewController <UISearchBarDelegate>

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
             stickers:(NoshiStickerLibrary *)stickers;

/* the new message screen of telegram for ios 4: set before the view loads, and the list is titled New Message with a row for a new group and one for a new channel over the
   contacts, which open into their chats as in the tab */
- (void)setComposeNewGroup:(void (^)(void))newGroup newChannel:(void (^)(void))newChannel;

@end

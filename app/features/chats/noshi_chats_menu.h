#import <UIKit/UIKit.h>

@class NoshiSession, NoshiAvatarCache, NoshiMediaCache, NoshiStickerLibrary;

/* the key of a new message at the right of the chat list, as telegram for ios 4 had it: the contacts under a row for a new group and one for a new channel. a new group
   asks for its people and then its name, a new channel for its name */
@interface NoshiChatsMenu : NSObject <UIAlertViewDelegate>

/* host is the controller the screens are pushed from, and refresh asks its list to load again (a group or a channel was made) */
- (id)initWithSession:(NoshiSession *)session host:(UIViewController *)host avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media
             stickers:(NoshiStickerLibrary *)stickers refresh:(void (^)(void))refresh;
/* pushes the new message screen over the host */
- (void)openCompose;

@end

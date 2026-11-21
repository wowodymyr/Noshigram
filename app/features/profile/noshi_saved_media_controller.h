#import "noshi_gift_screen.h"

@interface NoshiSavedMediaController : NoshiGiftScreen
- (id)initWithSession:(NoshiSession *)session dialog:(NoshiDialog *)dialog avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
@end

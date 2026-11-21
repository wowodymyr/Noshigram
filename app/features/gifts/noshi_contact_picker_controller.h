#import "noshi_avatar_cache.h"
#import "noshi_dialog.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_person.h"
#import "noshi_settings_kit.h"

/* the contacts in the cards of the settings, each with the picture of the person; a tap hands the chosen one to
   the caller as a chat with that person */
@interface NoshiContactPickerController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
@property (nonatomic, copy) NSString *screenTitle;
/* when set, the list starts with this person as "this is you"; choosing them hands over the chat with oneself */
@property (nonatomic, retain) NoshiPerson *selfPerson;
@property (nonatomic, copy) void (^pickHandler)(NoshiDialog *dialog);

@end

#import "noshi_avatar_cache.h"
#import "noshi_dialog.h"
#import "noshi_media_cache.h"
#import "noshi_session.h"
#import "noshi_settings_kit.h"

#import "noshi_dialog.h"

/* the chats of the person in the cards of the settings, each with its picture, narrowed by a rule, for a place to
   send something to or to hand to a bot */
@interface NoshiDialogPickerController : NoshiSettingsPageController

- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media;
@property (nonatomic, copy) NSString *screenTitle;
@property (nonatomic, assign) BOOL forwarding;
/* decides which chats are listed; nil lists every chat the person can open */
@property (nonatomic, copy) BOOL (^filter)(NoshiDialog *dialog);
/* how many chats may be picked, at least 1 */
@property (nonatomic, assign) NSUInteger limit;
/* the picked chats, once; not called when the person goes back */
@property (nonatomic, copy) void (^pickHandler)(NSArray *dialogs);
/* once, when the picker leaves the screen without a pick (back, or the controller dropped from the stack), never after pickHandler */
@property (nonatomic, copy) void (^cancelHandler)(void);
/* the picker as the first page of a navigation of its own, for a screen that is not in a navigation stack; picking or going back dismisses it */
- (UINavigationController *)presentableNavigation;

@end

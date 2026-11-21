#import "noshi_gift_screen.h"
#import "noshi_session_channels.h"

typedef enum {
    NoshiChannelFieldTitle,
    NoshiChannelFieldAbout,
    /* the public name of the channel: only what a name can hold goes in, and the server is asked whether it is free while the person types */
    NoshiChannelFieldUsername,
    /* the title an admin shows next to the name */
    NoshiChannelFieldRank,
    /* the name an admin gives an invite link */
    NoshiChannelFieldInviteTitle
} NoshiChannelFieldKind;

/* one text field on a card with a line of explanation under it, and the action that saves it; the screen goes back
   after a save that worked and shows the error otherwise */
@interface NoshiChannelFieldController : NoshiGiftScreen <UITextFieldDelegate>

/* dialog is the channel whose name is being checked, needed for the username kind only */
- (id)initWithSession:(NoshiSession *)session avatars:(NoshiAvatarCache *)avatars media:(NoshiMediaCache *)media kind:(NoshiChannelFieldKind)kind
                 text:(NSString *)text dialog:(NoshiDialog *)dialog save:(void (^)(NSString *text, void (^done)(NSString *errorName)))save;

@end

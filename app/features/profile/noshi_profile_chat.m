#import "noshi_profile_chat.h"

#import "noshi_chat_controller.h"
#import "noshi_classic_topics_controller.h"
#import "noshi_topics_screen.h"

void NoshiProfileShowChat(UIViewController *profile, NoshiSession *session, NoshiDialog *dialog, NoshiAvatarCache *avatars,
                            NoshiMediaCache *media, NoshiStickerLibrary *stickers) {
    UINavigationController *navigation = profile.navigationController;
    NSArray *stack = navigation.viewControllers;
    NSUInteger at = [stack indexOfObject:profile];
    /* a forum is not one chat but its topics: the way into it is the list of topics, the one the profile was opened from when it is still below, or else a new one */
    BOOL forum = dialog.forum && !dialog.topicId;
    if (at != NSNotFound && at > 0) {
        UIViewController *below = [stack objectAtIndex:at - 1];
        if (forum && [below isKindOfClass:[NoshiClassicTopicsController class]] && [(id)below showsForum:dialog]) {
            [navigation popViewControllerAnimated:YES];
            return;
        }
        if (!forum && [below isKindOfClass:[NoshiChatController class]] && [(NoshiChatController *)below showsDialog:dialog]) {
            [navigation popViewControllerAnimated:YES];
            return;
        }
    }
    if (forum) {
        [navigation pushViewController:NoshiTopicsScreen(session, dialog, avatars, media, stickers, nil) animated:YES];
        return;
    }
    NoshiChatController *chat = [[[NoshiChatController alloc] initWithSession:session dialog:dialog avatars:avatars media:media stickers:stickers] autorelease];
    [navigation pushViewController:chat animated:YES];
}

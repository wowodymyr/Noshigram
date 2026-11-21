#import "noshi_community_screen.h"

#import "noshi_classic_community_controller.h"
#import "noshi_theme.h"

UIViewController *NoshiCommunityScreen(NoshiSession *session, NoshiDialog *community, NSArray *known, NoshiAvatarCache *avatars,
                                         NoshiMediaCache *media, NoshiStickerLibrary *stickers, void (^closeHandler)(void)) {
    NoshiClassicCommunityController *screen = [[[NoshiClassicCommunityController alloc] initWithSession:session community:community known:known
                                                                                                     avatars:avatars media:media stickers:stickers] autorelease];
    screen.hidesBottomBarWhenPushed = YES;
    screen.closeHandler = closeHandler;
    return screen;
}

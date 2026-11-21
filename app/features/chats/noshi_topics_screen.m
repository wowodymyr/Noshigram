#import "noshi_topics_screen.h"

#import "noshi_classic_topics_controller.h"
#import "noshi_platform.h"
#import "noshi_theme.h"

UIViewController *NoshiTopicsScreenWithChats(NoshiSession *session, NoshiDialog *forum, NSArray *dialogs, NoshiAvatarCache *avatars, NoshiMediaCache *media,
                                               NoshiStickerLibrary *stickers, void (^archiveHandler)(void), void (^closeHandler)(void)) {
    NoshiClassicTopicsController *topics = [[[NoshiClassicTopicsController alloc] initWithSession:session forum:forum avatars:avatars
                                                                                               media:media stickers:stickers] autorelease];
    topics.hidesBottomBarWhenPushed = YES;
    topics.closeHandler = closeHandler;
    return topics;
}

UIViewController *NoshiTopicsScreen(NoshiSession *session, NoshiDialog *forum, NoshiAvatarCache *avatars, NoshiMediaCache *media,
                                      NoshiStickerLibrary *stickers, void (^closeHandler)(void)) {
    return NoshiTopicsScreenWithChats(session, forum, nil, avatars, media, stickers, nil, closeHandler);
}

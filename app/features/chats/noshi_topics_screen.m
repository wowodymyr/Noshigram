#import "noshi_topics_screen.h"

#import "noshi_classic_topics_controller.h"
#import "noshi_forum_controller.h"
#import "noshi_platform.h"
#import "noshi_theme.h"
#import "noshi_topics_controller.h"

UIViewController *NoshiTopicsScreenWithChats(NoshiSession *session, NoshiDialog *forum, NSArray *dialogs, NoshiAvatarCache *avatars, NoshiMediaCache *media,
                                               NoshiStickerLibrary *stickers, void (^archiveHandler)(void), void (^closeHandler)(void)) {
    if (NoshiThemeIsClassic()) {
        NoshiClassicTopicsController *topics = [[[NoshiClassicTopicsController alloc] initWithSession:session forum:forum avatars:avatars
                                                                                                   media:media stickers:stickers] autorelease];
        topics.hidesBottomBarWhenPushed = YES;
        topics.closeHandler = closeHandler;
        return topics;
    }
    /* the saved messages list the chats their messages came from, which the plain list of the topics already shows */
    if (!NoshiIsPad() && !forum.saved) {
        NoshiForumController *screen = [[[NoshiForumController alloc] initWithSession:session forum:forum dialogs:dialogs avatars:avatars
                                                                                    media:media stickers:stickers] autorelease];
        screen.archiveHandler = archiveHandler;
        screen.closeHandler = closeHandler;
        return screen;
    }
    NoshiTopicsController *topics = [[[NoshiTopicsController alloc] initWithSession:session forum:forum avatars:avatars
                                                                                   media:media stickers:stickers] autorelease];
    topics.closeHandler = closeHandler;
    return topics;
}

UIViewController *NoshiTopicsScreen(NoshiSession *session, NoshiDialog *forum, NoshiAvatarCache *avatars, NoshiMediaCache *media,
                                      NoshiStickerLibrary *stickers, void (^closeHandler)(void)) {
    return NoshiTopicsScreenWithChats(session, forum, nil, avatars, media, stickers, nil, closeHandler);
}

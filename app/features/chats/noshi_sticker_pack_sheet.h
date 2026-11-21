#import <UIKit/UIKit.h>

#import "noshi_media_cache.h"
#import "noshi_message.h"
#import "noshi_session.h"

/* the window a tap on a sticker of a chat opens, the one */
@interface NoshiStickerPackSheet : UIView

/* the sticker that was tapped, which names the pack; nothing is shown when it names none */
+ (BOOL)presentInView:(UIView *)host forSticker:(NoshiMedia *)sticker session:(NoshiSession *)session media:(NoshiMediaCache *)media
               sender:(void (^)(NoshiMedia *sticker))sender;

@end

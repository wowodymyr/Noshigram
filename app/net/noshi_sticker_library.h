#import <Foundation/Foundation.h>

#import "noshi_session.h"

/* the sticker sets the person has installed and the stickers they used lately, fetched on first use and kept for the
   life of the app; every call answers on the main thread */
@interface NoshiStickerLibrary : NSObject {
    NoshiSession *_session;
}

- (id)initWithSession:(NoshiSession *)session;

/* the installed sets in the person's order; an error name when they could not be fetched, and then nothing is kept
   so the next call asks again */
- (void)loadSets:(void (^)(NSArray *sets, NSString *errorName))completion;
- (void)loadStickersOfSet:(NoshiStickerSet *)set completion:(void (^)(NSArray *stickers, NSString *errorName))completion;
/* recently used stickers; fetched every time, they change with each send */
- (void)loadRecent:(void (^)(NSArray *stickers, NSString *errorName))completion;
/* the favorites and the saved animations; fetched every time, since the person changes them from the panel */
- (void)loadFaved:(void (^)(NSArray *stickers, NSString *errorName))completion;
- (void)loadGifs:(void (^)(NSArray *gifs, NSString *errorName))completion;
- (void)faveSticker:(NoshiSticker *)sticker unfave:(BOOL)unfave completion:(void (^)(NSString *errorName))completion;
- (void)clearRecent:(void (^)(NSString *errorName))completion;
/* nil without an error means Telegram has no supported animation for this emoji */
- (void)loadAnimationForEmoji:(NSString *)emoji completion:(void (^)(NoshiSticker *sticker, NSString *errorName))completion;

/* the animations of a game emoji (dice, darts, basketball, football, bowling, slots) in set order, see NoshiSession loadDiceStickersForEmoji:; kept for the life of the app once they
   came, and a failed request is not repeated for half a minute so a screenful of throws does not ask for each */
- (void)loadDiceForEmoji:(NSString *)emoji completion:(void (^)(NSArray *stickers, NSString *errorName))completion;

@end
